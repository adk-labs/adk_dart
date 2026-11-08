part of 'workflow.dart';

/// Returns the confirmation interrupt identifier for [nodePath].
String confirmationInterruptId(String nodePath) =>
    'wf_tool_confirmation:$nodePath';

/// Error thrown when a workflow graph fails static validation.
class GraphValidationError extends ArgumentError {
  /// Creates a graph validation error with [message].
  GraphValidationError([super.message]);
}

/// Error thrown when a workflow, node, or edge is configured invalidly.
class WorkflowConfigurationError extends ArgumentError {
  /// Creates a workflow configuration error with [message].
  WorkflowConfigurationError([super.message]);
}

/// Error thrown when runtime workflow data does not match node expectations.
class WorkflowDataError extends ArgumentError {
  /// Creates a workflow data error with [message].
  WorkflowDataError([super.message]);
}

/// Error thrown when an internal workflow runtime invariant is violated.
class WorkflowInvariantError extends StateError {
  /// Creates a workflow invariant error with [message].
  WorkflowInvariantError(super.message);
}

/// Chronological barrier used to coordinate deterministic replay ordering.
///
/// Keys not present in [sequence] pass through [wait] immediately. Keys in the
/// sequence are released one at a time as [checkAndAdvance] observes the
/// expected key, matching Python's replay barrier semantics.
class ReplaySequenceBarrier {
  /// Creates a replay sequence barrier.
  ReplaySequenceBarrier(Iterable<String> sequence, {Iterable<String>? pending})
    : sequence = List<String>.unmodifiable(sequence),
      pending = Set<String>.unmodifiable(pending ?? const <String>{}) {
    for (final String key in this.sequence) {
      _events.putIfAbsent(key, Completer<void>.new);
    }
    if (this.sequence.isNotEmpty) {
      _events[this.sequence.first]?.complete();
    }
  }

  /// Chronological replay key sequence.
  final List<String> sequence;

  /// Keys in [sequence] that were interrupted and not yet completed.
  final Set<String> pending;

  /// Current expected sequence index.
  int currentIndex = 0;

  final Map<String, Completer<void>> _events = <String, Completer<void>>{};
  final Set<String> _completed = <String>{};

  /// Waits until [key] is released, or returns immediately for unknown keys.
  Future<void> wait(String key) {
    return _events[key]?.future ?? Future<void>.value();
  }

  /// Advances the barrier through all completed keys at the head of [sequence].
  void checkAndAdvance(String key) {
    _completed.add(key);
    while (currentIndex < sequence.length &&
        _completed.contains(sequence[currentIndex])) {
      currentIndex += 1;
      if (currentIndex < sequence.length) {
        final Completer<void>? next = _events[sequence[currentIndex]];
        if (next != null && !next.isCompleted) {
          next.complete();
        }
      }
    }
  }

  /// Whether [key] is a replay key that has already been released.
  bool isReleased(String key) => _events[key]?.isCompleted ?? true;
}

/// Function callback signature for [FunctionNode].
typedef WorkflowFunction =
    FutureOr<Object?> Function(WorkflowContext context, Object? nodeInput);

/// Retry configuration for workflow node execution.
class RetryConfig {
  /// Creates retry configuration.
  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
    this.backoffMultiplier = 2,
    this.jitter = 1.0,
    this.exceptions,
  }) : assert(jitter >= 0, 'jitter must be non-negative.');

  /// Maximum number of attempts including the first run.
  ///
  /// This default applies only when a node explicitly sets [BaseNode.retryConfig].
  /// Nodes without retry config still run once.
  final int maxAttempts;

  /// Delay before the first retry.
  ///
  /// Defaults to the Python workflow runtime's 1 second. Use [Duration.zero]
  /// for immediate retries.
  final Duration initialDelay;

  /// Maximum delay between retries.
  ///
  /// Defaults to the Python workflow runtime's 60 seconds.
  final Duration maxDelay;

  /// Exponential backoff multiplier.
  final double backoffMultiplier;

  /// Randomness factor applied to retry delay.
  ///
  /// A value of `0.0` disables jitter. A value of `0.5` randomizes the delay
  /// within +/-50% of the calculated backoff delay. Defaults to Python's
  /// `1.0` behavior.
  final double jitter;

  /// Optional retry filter by exception class name or exact [Type].
  ///
  /// A `null` value retries all thrown exceptions until [maxAttempts] is
  /// reached. An empty list retries none.
  final List<Object>? exceptions;
}

/// Error thrown when a node exceeds its timeout.
class NodeTimeoutError implements Exception {
  /// Creates a node timeout error.
  NodeTimeoutError({required this.nodeName, required this.timeout});

  /// Timed-out node name.
  final String nodeName;

  /// Timeout that was exceeded.
  final Duration timeout;

  @override
  String toString() {
    return 'NodeTimeoutError: node `$nodeName` exceeded $timeout.';
  }
}

/// Runtime status for a workflow node.
enum NodeStatus {
  /// Node is not ready to run.
  inactive,

  /// Node has not started yet.
  pending,

  /// Node is currently running.
  running,

  /// Node completed successfully.
  completed,

  /// Node is waiting for user input or another trigger.
  waiting,

  /// Node failed.
  failed,

  /// Node was cancelled.
  cancelled,

  /// Legacy alias for [completed].
  succeeded,
}

/// Mutable state for one workflow node.
class NodeState {
  /// Creates node state.
  NodeState({
    this.status = NodeStatus.inactive,
    this.input,
    this.attemptCount = 1,
    List<String>? interrupts,
    Map<String, Object?>? resumeInputs,
    List<String>? outputFor,
    this.branch,
    this.outputBranch,
    this.runCounter = 0,
    this.runId,
    this.parentRunId,
    this.parentKey,
    this.route,
    this.error,
  }) : interrupts = interrupts ?? <String>[],
       outputFor = outputFor ?? <String>[],
       resumeInputs = resumeInputs ?? <String, Object?>{};

  /// Current node status.
  NodeStatus status;

  /// Input provided to this node run.
  Object? input;

  /// Number of attempts performed.
  int attemptCount;

  /// Interrupt identifiers currently waiting for a response.
  final List<String> interrupts;

  /// Resume input values keyed by interrupt identifier.
  final Map<String, Object?> resumeInputs;

  /// Output ownership targets for delegated workflow outputs.
  final List<String> outputFor;

  /// Branch used when executing this node.
  String? branch;

  /// Branch of the outermost node that explicitly claimed this node's output.
  String? outputBranch;

  /// Sequential run counter for fresh node runs.
  int runCounter;

  /// Current node run identifier.
  String? runId;

  /// Parent dynamic node run identifier, when applicable.
  String? parentRunId;

  /// Parent node state key when scheduled dynamically via [WorkflowContext.runNode].
  String? parentKey;

  /// Last route emitted by this node.
  Object? route;

  /// Last error, if any.
  Object? error;
}

/// Shared runtime context passed to workflow nodes.
class WorkflowContext {
  /// Creates a workflow context.
  WorkflowContext({
    this.invocationContext,
    this.input,
    Map<String, Object?>? outputs,
    Map<String, NodeState>? nodeStates,
    Map<String, Object?>? resumeInputs,
    Map<String, List<Event>>? nodeEvents,
    Map<String, Event>? nodeOutputEvents,
    Set<String>? requestInputNodeKeys,
    Map<String, Object?>? fallbackState,
    String? workflowRoot,
    this.onNodeStateChange,
  }) : outputs = outputs ?? <String, Object?>{},
       nodeStates = nodeStates ?? <String, NodeState>{},
       resumeInputs = resumeInputs ?? <String, Object?>{},
       _nodeEvents = nodeEvents ?? <String, List<Event>>{},
       _nodeOutputEvents = nodeOutputEvents ?? <String, Event>{},
       requestInputNodeKeys = requestInputNodeKeys ?? <String>{},
       _fallbackState = fallbackState ?? <String, Object?>{},
       _workflowRoot = workflowRoot,
       _cancellation = _WorkflowCancelToken() {
    _seedChildRunCounters();
  }

  WorkflowContext._({
    this.invocationContext,
    this.input,
    required _WorkflowCancelToken cancellation,
    Map<String, Object?>? outputs,
    Map<String, NodeState>? nodeStates,
    Map<String, Object?>? resumeInputs,
    Map<String, List<Event>>? nodeEvents,
    Map<String, Event>? nodeOutputEvents,
    Set<String>? requestInputNodeKeys,
    required Map<String, Object?> fallbackState,
    String? workflowRoot,
    this.onNodeStateChange,
  }) : outputs = outputs ?? <String, Object?>{},
       nodeStates = nodeStates ?? <String, NodeState>{},
       resumeInputs = resumeInputs ?? <String, Object?>{},
       _nodeEvents = nodeEvents ?? <String, List<Event>>{},
       _nodeOutputEvents = nodeOutputEvents ?? <String, Event>{},
       requestInputNodeKeys = requestInputNodeKeys ?? <String>{},
       _fallbackState = fallbackState,
       _workflowRoot = workflowRoot,
       _cancellation = cancellation {
    _seedChildRunCounters();
  }

  bool _hasDirectOutput = false;
  Object? _directOutput;
  bool _outputDelegated = false;
  bool _failedInDynamicChild = false;
  final Map<String, int> _childRunCounters = <String, int>{};
  String? _currentNodeKey;
  bool? _currentNodeRerunOnResume;
  final Map<String, List<Event>> _nodeEvents;
  final Map<String, Event> _nodeOutputEvents;
  final Map<String, Object?> _fallbackState;
  final String? _workflowRoot;
  final _WorkflowCancelToken _cancellation;

  /// ADK invocation context when running as an agent.
  final InvocationContext? invocationContext;

  /// Initial workflow input.
  final Object? input;

  /// Callback invoked whenever a node's state or status changes.
  void Function()? onNodeStateChange;

  /// Set of request input node keys in this workflow.
  final Set<String> requestInputNodeKeys;

  // Intermediate checkpoint events.
  final List<Event> _checkpointEvents = <Event>[];

  /// Node outputs keyed by node name.
  final Map<String, Object?> outputs;

  /// Node states keyed by node name.
  final Map<String, NodeState> nodeStates;

  /// Resume payloads keyed by interrupt identifier.
  final Map<String, Object?> resumeInputs;

  /// Resumed tool confirmation for the current node run, when present.
  ToolConfirmation? toolConfirmation;

  /// Mutable session state map (or a fallback map when running standalone).
  Map<String, Object?> get state =>
      invocationContext?.session.state ?? _fallbackState;

  /// Path of the currently executing node within its workflow.
  String get nodePath {
    final String key = _currentNodeKey ?? '';
    final String runId = nodeStates[key]?.runId ?? '1';
    final String segment = key.isEmpty
        ? 'node@$runId'
        : (key.contains('@') ? key : '$key@$runId');
    final String? root =
        _workflowRoot ??
        (invocationContext != null
            ? (invocationContext!.branch?.isNotEmpty == true
                  ? invocationContext!.branch!
                  : '${invocationContext!.agent.name.isEmpty ? 'workflow' : invocationContext!.agent.name}@1')
            : null);
    if (root == null || root.isEmpty) {
      return segment;
    }
    return '$root/$segment';
  }

  /// Whether this workflow context has observed cancellation.
  bool get isCancelled =>
      invocationContext?.isAborted == true || _cancellation.cancelled;

  /// Throws [AdkAbortException] when the workflow has been cancelled.
  void throwIfCancelled() {
    invocationContext?.abortSignal?.throwIfAborted();
    if (_cancellation.cancelled) {
      throw AdkAbortException(_cancellation.reason);
    }
  }

  /// Route emitted directly by the current node.
  Object? route;

  /// Interrupt identifiers emitted directly by the current node.
  final Set<String> interruptIds = <String>{};

  /// Output emitted directly by the current node.
  Object? get output => _directOutput;

  /// Sets direct output for the current node.
  ///
  /// A node may set a non-null output once. Setting output more than once, or
  /// setting it while also returning an output value, is treated as a workflow
  /// authoring error. A null value is treated as no output.
  set output(Object? value) {
    if (_hasDirectOutput) {
      throw StateError('Workflow node output is already set.');
    }
    if (value == null) {
      _directOutput = null;
      return;
    }
    _hasDirectOutput = true;
    _directOutput = value;
  }

  /// Reads an output by node [name].
  Object? outputOf(String name) => outputs[name];

  /// Runs [nodeLike] immediately as a dynamic child node.
  ///
  /// The child node shares this workflow context, records its output in
  /// [outputs], and records execution state in [nodeStates]. When the context is
  /// owned by a [Workflow], the same retry and timeout behavior used by static
  /// graph nodes is applied.
  ///
  /// State and output are recorded under `nodeName@runId` so multiple dynamic
  /// instances of the same node can be resumed or deduplicated independently.
  /// When [runId] is omitted, a per-caller numeric ID is generated from the
  /// child node name. Explicit run IDs must contain at least one non-numeric
  /// character to avoid collisions with auto-generated numeric run IDs.
  ///
  /// When [useAsOutput] is true, the dynamic child output is treated as the
  /// caller's delegated output and the caller's own output is suppressed.
  /// [overrideBranch] replaces the inherited branch for the child output event.
  /// When [useSubBranch] is true, the child output event branch appends the
  /// generated `nodeName@runId` segment to the inherited or overridden branch.
  /// When called from a workflow node, the caller node must set
  /// `rerunOnResume: true` so interrupted dynamic children can be replayed
  /// safely during workflow resume.
  Future<Object?> runNode(
    Object nodeLike, {
    Object? input,
    String? name,
    String? runId,
    bool useAsOutput = false,
    bool useSubBranch = false,
    String? overrideBranch,
    String description = '',
    bool? rerunOnResume,
    bool? waitForOutput,
    RetryConfig? retryConfig,
    Duration? timeout,
    bool raiseOnWait = false,
  }) async {
    throwIfCancelled();
    if (_currentNodeRerunOnResume == false) {
      throw StateError(
        'A workflow node must have rerunOnResume: true before it can '
        'schedule dynamic child nodes.',
      );
    }
    final BaseNode node = buildNode(
      nodeLike,
      name: name,
      description: description,
      rerunOnResume: rerunOnResume,
      waitForOutput: waitForOutput,
      retryConfig: retryConfig,
      timeout: timeout,
    );
    if (runId != null && int.tryParse(runId) != null) {
      throw ArgumentError.value(
        runId,
        'runId',
        'Explicit dynamic workflow run IDs must contain non-numeric characters.',
      );
    }
    if (useAsOutput) {
      if (_outputDelegated) {
        throw StateError('Workflow node already has a delegated output.');
      }
      _outputDelegated = true;
    }
    final String effectiveRunId = runId ?? _nextDynamicRunId(node.name);
    final String stateKey = '${node.name}@$effectiveRunId';
    if (node is RequestInput) {
      requestInputNodeKeys.add(stateKey);
    }
    final String? parentKey = _currentNodeKey;
    final NodeState? parentState = parentKey == null
        ? null
        : nodeStates[parentKey];
    final String? branch = _dynamicNodeBranch(
      nodeKey: stateKey,
      parentBranch: parentState?.branch ?? invocationContext?.branch,
      useSubBranch: useSubBranch,
      overrideBranch: overrideBranch,
    );
    final NodeState? state = nodeStates[stateKey];
    final String? claimerBranch = useAsOutput
        ? (parentState?.outputBranch ??
              parentState?.branch ??
              invocationContext?.branch)
        : null;
    if (state != null) {
      state.parentKey ??= parentKey;
      if (branch != null) {
        state.branch = branch;
      }
      if (useAsOutput) {
        state.outputBranch = claimerBranch;
      }
      if (_isCompletedNodeState(state) && outputs.containsKey(stateKey)) {
        if (useAsOutput && state.route != null) {
          route ??= state.route;
        }
        return outputs[stateKey];
      }
      _seedNodeResumeInputs(
        state,
        resumeInputs,
        rerunOnResume: node.rerunOnResume,
      );
      final bool hasPendingChildInterrupts = nodeStates.entries.any(
        (MapEntry<String, NodeState> e) =>
            e.value.parentKey == stateKey && e.value.interrupts.isNotEmpty,
      );
      if (state.status != NodeStatus.failed) {
        if (_hasUnresolvedWaitingInterrupts(
          state,
          rerunOnResume: node.rerunOnResume && hasPendingChildInterrupts,
        )) {
          interruptIds.addAll(state.interrupts);
          if (raiseOnWait) {
            throw NodeInterruptedError(interruptIds: state.interrupts);
          }
          return outputs[stateKey];
        }
        if (state.status == NodeStatus.waiting &&
            state.resumeInputs.isNotEmpty &&
            !node.rerunOnResume) {
          final Object? output = _outputFromResumeInputs(state.resumeInputs);
          outputs[stateKey] = output;
          state.status = NodeStatus.completed;
          state.interrupts.clear();
          state.resumeInputs.clear();
          return output;
        }
      }
    } else if (branch != null || useAsOutput) {
      nodeStates[stateKey] = NodeState(
        parentKey: parentKey,
        branch: branch,
        outputBranch: claimerBranch,
      );
    }
    final WorkflowContext childContext = _childExecutionContext(
      resumeInputs: state?.resumeInputs.isNotEmpty == true
          ? Map<String, Object?>.from(state!.resumeInputs)
          : const <String, Object?>{},
    );
    final Object? rawOutput;
    try {
      rawOutput = await _runNodeWithRetry(
        context: childContext,
        node: node,
        nodeInput: input,
        stateKey: stateKey,
        runId: effectiveRunId,
        parentKey: parentKey,
      );
    } on NodeInterruptedError catch (error) {
      interruptIds
        ..addAll(childContext.interruptIds)
        ..addAll(error.interruptIds);
      if (raiseOnWait) {
        rethrow;
      }
      return outputs[stateKey];
    } catch (_) {
      _failedInDynamicChild = true;
      rethrow;
    }
    if (branch != null) {
      nodeStates[stateKey]?.branch = branch;
    }
    if (useAsOutput) {
      nodeStates[stateKey]?.outputBranch = claimerBranch;
    }
    final _NodeRunResult result = _resultFromRawNodeOutput(
      node,
      rawOutput,
      context: childContext,
      name: stateKey,
    );
    if (useAsOutput) {
      final NodeState? childState = nodeStates[stateKey];
      if (childState != null && parentKey != null) {
        childState.outputFor
          ..clear()
          ..add(stateKey)
          ..addAll(
            parentState?.outputFor.isNotEmpty == true
                ? parentState!.outputFor
                : <String>[parentKey],
          );
      }
    }
    _recordNodeResult(this, result);
    if (useAsOutput && result.route != null) {
      route ??= result.route;
    }
    if (result.interruptIds.isNotEmpty) {
      interruptIds.addAll(result.interruptIds);
    }
    if (raiseOnWait && (result.waiting || result.interruptIds.isNotEmpty)) {
      throw NodeInterruptedError(interruptIds: result.interruptIds);
    }
    return result.output;
  }

  /// Records every numeric `runId` in [nodePath] as allocated so future dynamic
  /// runs of the same node or its ancestors do not reuse that path.
  void reserveRunIds(String nodePath) {
    if (nodePath.isEmpty) {
      return;
    }
    NodePathBuilder? path = NodePathBuilder.fromString(nodePath);
    while (path != null && path.toString().isNotEmpty) {
      final String? runId = path.runId;
      final int? parsed = runId == null ? null : int.tryParse(runId);
      if (parsed != null && parsed > 0 && path.nodeName.isNotEmpty) {
        final int current = _childRunCounters[path.nodeName] ?? 0;
        if (parsed > current) {
          _childRunCounters[path.nodeName] = parsed;
        }
      }
      path = path.parent;
    }
  }

  void _seedChildRunCounters() {
    if (_workflowRoot != null && _workflowRoot.isNotEmpty) {
      reserveRunIds(_workflowRoot);
    }
    final String? branch = invocationContext?.branch;
    if (branch != null && branch.isNotEmpty) {
      reserveRunIds(branch);
    }
    for (final String key in nodeStates.keys) {
      reserveRunIds(key);
    }
    final List<Event>? events = invocationContext?.session.events;
    final String? invocationId = invocationContext?.invocationId;
    if (events != null) {
      for (final Event event in events) {
        if (invocationId != null &&
            invocationId.isNotEmpty &&
            event.invocationId != invocationId) {
          continue;
        }
        if (event.nodeInfo.path.isNotEmpty) {
          reserveRunIds(event.nodeInfo.path);
        }
      }
    }
  }

  String? _dynamicNodeBranch({
    required String nodeKey,
    required String? parentBranch,
    required bool useSubBranch,
    required String? overrideBranch,
  }) {
    final String? baseBranch = overrideBranch ?? parentBranch;
    if (useSubBranch) {
      // [nodeKey] is already a `name@runId` segment, so append it as-is.
      return BranchPath.createSubBranch(baseBranch, name: nodeKey);
    }
    return overrideBranch;
  }

  String _nextDynamicRunId(String nodeName) {
    final int next = (_childRunCounters[nodeName] ?? 0) + 1;
    _childRunCounters[nodeName] = next;
    return '$next';
  }

  WorkflowContext _childExecutionContext({Map<String, Object?>? resumeInputs}) {
    return WorkflowContext._(
      invocationContext: invocationContext,
      input: input,
      cancellation: _cancellation,
      outputs: outputs,
      nodeStates: nodeStates,
      resumeInputs: resumeInputs ?? this.resumeInputs,
      nodeEvents: _nodeEvents,
      nodeOutputEvents: _nodeOutputEvents,
      requestInputNodeKeys: requestInputNodeKeys,
      fallbackState: _fallbackState,
      workflowRoot: _workflowRoot,
      onNodeStateChange: onNodeStateChange,
    );
  }

  void _cancel(Object? reason) {
    _cancellation.cancel(reason);
  }
}

class _WorkflowCancelToken {
  bool cancelled = false;
  Object? reason;

  void cancel(Object? reason) {
    if (cancelled) {
      return;
    }
    cancelled = true;
    this.reason = reason;
  }
}

/// Execution result from [Workflow.runWorkflow].
class WorkflowResult {
  /// Creates workflow result.
  WorkflowResult({required this.outputs, required this.nodeStates});

  /// Node outputs keyed by node name.
  final Map<String, Object?> outputs;

  /// Final node states keyed by node name.
  final Map<String, NodeState> nodeStates;
}
