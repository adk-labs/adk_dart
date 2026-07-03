/// Experimental node-based workflow runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../agents/abort_signal.dart';
import '../agents/base_agent.dart';
import '../agents/context.dart';
import '../agents/invocation_context.dart';
import '../agents/llm_agent.dart';
import '../events/event.dart';
import '../events/node_path_builder.dart';
import '../events/request_input.dart';
import '../flows/llm_flows/functions.dart';
import '../sessions/in_memory_session_service.dart';
import '../sessions/session.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';

/// Sentinel node name used for workflow start edges.
// ignore: constant_identifier_names
const String START = 'START';

/// Default route value used by routed workflow edges.
// ignore: constant_identifier_names
const String DEFAULT_ROUTE = '__DEFAULT__';

const String _workflowOutputOwner = r'$workflow';

/// Chronological barrier used to coordinate deterministic replay ordering.
///
/// Keys not present in [sequence] pass through [wait] immediately. Keys in the
/// sequence are released one at a time as [checkAndAdvance] observes the
/// expected key, matching Python's replay barrier semantics.
class ReplaySequenceBarrier {
  /// Creates a replay sequence barrier.
  ReplaySequenceBarrier(Iterable<String> sequence)
    : sequence = List<String>.unmodifiable(sequence) {
    for (final String key in this.sequence) {
      _events.putIfAbsent(key, Completer<void>.new);
    }
    if (this.sequence.isNotEmpty) {
      _events[this.sequence.first]?.complete();
    }
  }

  /// Chronological replay key sequence.
  final List<String> sequence;

  /// Current expected sequence index.
  int currentIndex = 0;

  final Map<String, Completer<void>> _events = <String, Completer<void>>{};

  /// Waits until [key] is released, or returns immediately for unknown keys.
  Future<void> wait(String key) {
    return _events[key]?.future ?? Future<void>.value();
  }

  /// Advances the barrier if [key] is the current expected replay key.
  void checkAndAdvance(String key) {
    if (currentIndex >= sequence.length) {
      return;
    }
    if (key != sequence[currentIndex]) {
      return;
    }
    currentIndex += 1;
    if (currentIndex >= sequence.length) {
      return;
    }
    final Completer<void>? next = _events[sequence[currentIndex]];
    if (next != null && !next.isCompleted) {
      next.complete();
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
  /// This default applies only when a node explicitly sets [retryConfig].
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
    this.runCounter = 0,
    this.runId,
    this.parentRunId,
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

  /// Branch used when emitting this node's output event.
  String? branch;

  /// Sequential run counter for fresh node runs.
  int runCounter;

  /// Current node run identifier.
  String? runId;

  /// Parent dynamic node run identifier, when applicable.
  String? parentRunId;

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
  }) : outputs = outputs ?? <String, Object?>{},
       nodeStates = nodeStates ?? <String, NodeState>{},
       resumeInputs = resumeInputs ?? <String, Object?>{},
       _nodeEvents = nodeEvents ?? <String, List<Event>>{},
       _nodeOutputEvents = nodeOutputEvents ?? <String, Event>{},
       _cancellation = _WorkflowCancelToken();

  WorkflowContext._({
    this.invocationContext,
    this.input,
    required _WorkflowCancelToken cancellation,
    Map<String, Object?>? outputs,
    Map<String, NodeState>? nodeStates,
    Map<String, Object?>? resumeInputs,
    Map<String, List<Event>>? nodeEvents,
    Map<String, Event>? nodeOutputEvents,
  }) : outputs = outputs ?? <String, Object?>{},
       nodeStates = nodeStates ?? <String, NodeState>{},
       resumeInputs = resumeInputs ?? <String, Object?>{},
       _nodeEvents = nodeEvents ?? <String, List<Event>>{},
       _nodeOutputEvents = nodeOutputEvents ?? <String, Event>{},
       _cancellation = cancellation;

  bool _hasDirectOutput = false;
  Object? _directOutput;
  bool _outputDelegated = false;
  final Map<String, int> _childRunCounters = <String, int>{};
  String? _currentNodeKey;
  bool? _currentNodeRerunOnResume;
  final Map<String, List<Event>> _nodeEvents;
  final Map<String, Event> _nodeOutputEvents;
  final _WorkflowCancelToken _cancellation;

  /// ADK invocation context when running as an agent.
  final InvocationContext? invocationContext;

  /// Initial workflow input.
  final Object? input;

  /// Node outputs keyed by node name.
  final Map<String, Object?> outputs;

  /// Node states keyed by node name.
  final Map<String, NodeState> nodeStates;

  /// Resume payloads keyed by interrupt identifier.
  final Map<String, Object?> resumeInputs;

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
    if (branch != null && state != null) {
      state.branch = branch;
    }
    if (state != null) {
      if (_isCompletedNodeState(state) && outputs.containsKey(stateKey)) {
        return outputs[stateKey];
      }
      _seedNodeResumeInputs(state, resumeInputs);
      if (_hasUnresolvedWaitingInterrupts(state)) {
        interruptIds.addAll(state.interrupts);
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
    final WorkflowContext childContext = _childExecutionContext(
      resumeInputs: state?.resumeInputs.isNotEmpty == true
          ? Map<String, Object?>.from(state!.resumeInputs)
          : const <String, Object?>{},
    );
    final Object? rawOutput = await _runNodeWithRetry(
      context: childContext,
      node: node,
      nodeInput: input,
      stateKey: stateKey,
      runId: effectiveRunId,
    );
    if (branch != null) {
      nodeStates[stateKey]?.branch = branch;
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
    return result.output;
  }

  String? _dynamicNodeBranch({
    required String nodeKey,
    required String? parentBranch,
    required bool useSubBranch,
    required String? overrideBranch,
  }) {
    final String? baseBranch = overrideBranch ?? parentBranch;
    if (useSubBranch) {
      return baseBranch == null || baseBranch.isEmpty
          ? nodeKey
          : '$baseBranch.$nodeKey';
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

/// Base class for node-based workflow units.
abstract class BaseNode {
  /// Creates a workflow node.
  BaseNode({
    required this.name,
    this.description = '',
    List<String>? dependsOn,
    this.rerunOnResume = false,
    this.waitForOutput = false,
    this.retryConfig,
    this.timeout,
  }) : dependsOn = dependsOn ?? const <String>[];

  /// Stable node name.
  final String name;

  /// Human-readable node description.
  final String description;

  /// Names of predecessor nodes that must finish before this node runs.
  final List<String> dependsOn;

  /// Whether the node should rerun after resume.
  final bool rerunOnResume;

  /// Whether the workflow should wait for this output before proceeding.
  final bool waitForOutput;

  /// Optional retry configuration.
  final RetryConfig? retryConfig;

  /// Optional per-attempt timeout.
  final Duration? timeout;

  /// Runs this node with [nodeInput].
  FutureOr<Object?> run(WorkflowContext context, Object? nodeInput);
}

/// Node designed for subclassing.
abstract class Node extends BaseNode {
  /// Creates a subclassable workflow node.
  Node({
    required super.name,
    super.description,
    super.dependsOn,
    super.rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
  });
}

/// Function-backed workflow node.
class FunctionNode extends BaseNode {
  /// Creates a function-backed node.
  FunctionNode({
    required this.function,
    required super.name,
    super.description,
    super.dependsOn,
    super.rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
  });

  /// Function invoked for this node.
  final WorkflowFunction function;

  @override
  FutureOr<Object?> run(WorkflowContext context, Object? nodeInput) {
    return function(context, nodeInput);
  }
}

/// Convenience wrapper matching Python's `node(...)` helper.
FunctionNode node(
  WorkflowFunction function, {
  required String name,
  String description = '',
  List<String>? dependsOn,
  bool rerunOnResume = false,
  RetryConfig? retryConfig,
  Duration? timeout,
}) {
  return buildNode(
        function,
        name: name,
        description: description,
        dependsOn: dependsOn,
        rerunOnResume: rerunOnResume,
        retryConfig: retryConfig,
        timeout: timeout,
      )
      as FunctionNode;
}

/// Converts a workflow-compatible object into a [BaseNode].
///
/// Supports existing [BaseNode] instances, [BaseTool] values, [BaseAgent]
/// values, and [WorkflowFunction] callbacks.
///
/// Throws an [UnsupportedError] when overriding an existing node is requested
/// and an [ArgumentError] for unsupported values.
BaseNode buildNode(
  Object nodeLike, {
  String? name,
  String description = '',
  List<String>? dependsOn,
  bool? rerunOnResume,
  bool? waitForOutput,
  RetryConfig? retryConfig,
  Duration? timeout,
}) {
  if (nodeLike is BaseNode) {
    if (name == null &&
        description.isEmpty &&
        dependsOn == null &&
        rerunOnResume == null &&
        waitForOutput == null &&
        retryConfig == null &&
        timeout == null) {
      return nodeLike;
    }
    throw UnsupportedError(
      'Cannot override fields for existing node `${nodeLike.name}`.',
    );
  }
  if (nodeLike is BaseTool) {
    return ToolNode(
      tool: nodeLike,
      name: name,
      description: description,
      dependsOn: dependsOn,
      rerunOnResume: rerunOnResume ?? false,
      waitForOutput: waitForOutput ?? false,
      retryConfig: retryConfig,
      timeout: timeout,
    );
  }
  if (nodeLike is BaseAgent) {
    final bool agentWaitForOutput =
        waitForOutput ?? (nodeLike is LlmAgent && nodeLike.mode == 'task');
    return AgentNode(
      agent: nodeLike,
      name: name,
      description: description,
      dependsOn: dependsOn,
      rerunOnResume: rerunOnResume,
      waitForOutput: agentWaitForOutput,
      retryConfig: retryConfig,
      timeout: timeout,
    );
  }
  if (nodeLike is WorkflowFunction) {
    return FunctionNode(
      function: nodeLike,
      name: name ?? 'function_node',
      description: description,
      dependsOn: dependsOn,
      rerunOnResume: rerunOnResume ?? false,
      waitForOutput: waitForOutput ?? false,
      retryConfig: retryConfig,
      timeout: timeout,
    );
  }
  throw ArgumentError.value(
    nodeLike,
    'nodeLike',
    'Expected a BaseNode, BaseTool, BaseAgent, or WorkflowFunction.',
  );
}

/// Wraps [nodeLike] in a [ParallelWorker].
ParallelWorker parallelWorker(
  Object nodeLike, {
  int? maxConcurrency,
  int? maxParallelWorkers,
  RetryConfig? retryConfig,
  Duration? timeout,
}) {
  return ParallelWorker(
    node: nodeLike,
    maxConcurrency: maxConcurrency,
    maxParallelWorkers: maxParallelWorkers,
    retryConfig: retryConfig,
    timeout: timeout,
  );
}

/// Node that passes through aggregated predecessor inputs.
class JoinNode extends BaseNode {
  /// Creates a join node.
  JoinNode({
    required super.name,
    super.description,
    super.dependsOn,
    super.retryConfig,
    super.timeout,
  });

  @override
  Object? run(WorkflowContext context, Object? nodeInput) => nodeInput;
}

/// Node that runs a wrapped child node for every input item in parallel.
class ParallelWorker extends BaseNode {
  /// Creates a parallel worker node.
  factory ParallelWorker({
    required Object node,
    int? maxConcurrency,
    int? maxParallelWorkers,
    RetryConfig? retryConfig,
    Duration? timeout,
  }) {
    final BaseNode wrappedNode = _buildParallelWorkerNode(node);
    final int? resolvedLimit = maxParallelWorkers ?? maxConcurrency;
    if (resolvedLimit != null && resolvedLimit < 1) {
      throw ArgumentError('maxParallelWorkers must be greater than or equal to 1.');
    }
    return ParallelWorker._(
      wrappedNode: wrappedNode,
      maxParallelWorkers: resolvedLimit,
      retryConfig: retryConfig,
      timeout: timeout,
    );
  }

  ParallelWorker._({
    required this.wrappedNode,
    required this.maxParallelWorkers,
    super.retryConfig,
    super.timeout,
  }) : super(name: wrappedNode.name, rerunOnResume: true);

  /// Wrapped child node.
  final BaseNode wrappedNode;

  /// Maximum worker tasks to run at once. `null` means unlimited.
  final int? maxParallelWorkers;

  /// Deprecated. Use [maxParallelWorkers] instead.
  @deprecated
  int? get maxConcurrency => maxParallelWorkers;

  @override
  Future<List<Object?>> run(WorkflowContext context, Object? nodeInput) async {
    final List<Object?> items = nodeInput is List<Object?>
        ? nodeInput
        : nodeInput is List
        ? List<Object?>.from(nodeInput)
        : <Object?>[nodeInput];
    if (items.isEmpty) {
      return <Object?>[];
    }

    final List<Object?> results = List<Object?>.filled(items.length, null);
    final int limit = maxParallelWorkers == null || maxParallelWorkers! <= 0
        ? items.length
        : maxParallelWorkers!;
    int nextIndex = 0;
    var cancelRemaining = false;
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> worker() async {
      while (true) {
        if (cancelRemaining) {
          return;
        }
        final int index = nextIndex;
        nextIndex += 1;
        if (index >= items.length) {
          return;
        }
        try {
          results[index] = await context.runNode(
            wrappedNode,
            input: items[index],
            useSubBranch: true,
          );
        } catch (error, stackTrace) {
          cancelRemaining = true;
          firstError ??= error;
          firstStackTrace ??= stackTrace;
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
    }

    try {
      await Future.wait(<Future<void>>[
        for (int i = 0; i < limit && i < items.length; i += 1) worker(),
      ], eagerError: true);
    } catch (error, stackTrace) {
      cancelRemaining = true;
      Error.throwWithStackTrace(
        firstError ?? error,
        firstStackTrace ?? stackTrace,
      );
    }
    return results;
  }
}

BaseNode _buildParallelWorkerNode(Object node) {
  if (node == START) {
    throw ArgumentError.value(
      node,
      'node',
      'ParallelWorker cannot wrap a START node.',
    );
  }
  return buildNode(node);
}

/// Node that wraps an ADK [BaseTool].
class ToolNode extends BaseNode {
  /// Creates a tool-backed workflow node.
  ToolNode({
    required this.tool,
    String? name,
    super.description,
    super.dependsOn,
    super.rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
  }) : super(name: name ?? tool.name);

  /// Tool executed by this node.
  final BaseTool tool;

  @override
  Future<Object?> run(WorkflowContext context, Object? nodeInput) async {
    final Map<String, dynamic> args = _toolArgsFromInput(nodeInput);
    final InvocationContext invocationContext =
        context.invocationContext ?? _standaloneInvocationContext(name);
    final Context toolContext = Context(
      invocationContext,
      functionCallId: 'workflow-$name-${DateTime.now().microsecondsSinceEpoch}',
    );
    return tool.run(args: args, toolContext: toolContext);
  }
}

/// Node that wraps an ADK [BaseAgent].
class AgentNode extends BaseNode {
  /// Creates an agent-backed workflow node.
  AgentNode({
    required this.agent,
    String? name,
    super.description,
    super.dependsOn,
    bool? rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
  }) : super(name: name ?? agent.name, rerunOnResume: rerunOnResume ?? true);

  /// Agent executed by this node.
  final BaseAgent agent;

  @override
  Future<Object?> run(WorkflowContext context, Object? nodeInput) async {
    // As a node in a workflow, LlmAgent defaults to single_turn mode and
    // suppresses prior conversation contents unless the user explicitly
    // configured includeContents.
    // Matches adk-python _llm_agent_wrapper.run_llm_agent_as_node.
    if (agent is LlmAgent) {
      final LlmAgent llmAgent = agent as LlmAgent;
      if (llmAgent.mode == null) {
        llmAgent.mode = 'single_turn';
      }
      // Only default includeContents to 'none' when the user has not
      // explicitly set it (i.e. it is still at the constructor default
      // value of 'default').
      if (llmAgent.mode == 'single_turn' &&
          llmAgent.includeContents == 'default') {
        llmAgent.includeContents = 'none';
      }
    }

    final InvocationContext parentContext =
        context.invocationContext ?? _standaloneInvocationContext(name);
    final Content? userContent = nodeInput == null
        ? null
        : _contentFromNodeInput(nodeInput);
    final InvocationContext agentContext = parentContext.copyWith(
      agent: agent,
      userContent: userContent,
    );
    final String? nodeKey = context._currentNodeKey;
    final bool collectNestedWorkflowEvents =
        agent is Workflow &&
        nodeKey != null &&
        context.invocationContext != null;
    final String? ownerPath = collectNestedWorkflowEvents
        ? _nodePathForOutputKey(parentContext, nodeKey)
        : null;
    final List<Event> nestedEvents = <Event>[];

    Event? finalEvent;
    await for (final Event event in agent.runAsync(agentContext)) {
      _mergeStateDelta(agentContext.session, event.actions.stateDelta);
      if (event.isFinalResponse()) {
        finalEvent = event;
      }
      if (collectNestedWorkflowEvents) {
        nestedEvents.add(
          _rewriteNestedWorkflowEvent(
            event,
            nestedWorkflow: agent as Workflow,
            ownerPath: ownerPath!,
          ),
        );
      }
    }

    if (collectNestedWorkflowEvents && nestedEvents.isNotEmpty) {
      context._nodeEvents[nodeKey] = nestedEvents;
    }

    if (finalEvent == null) {
      return null;
    }
    return _outputFromAgentEvent(finalEvent);
  }
}

/// Directed workflow edge.
class Edge {
  /// Creates a workflow edge.
  Edge({required Object fromNode, required Object toNode, this.route})
    : fromNode = _nodeName(fromNode),
      toNode = _nodeName(toNode);

  /// Source node name or [START].
  final String fromNode;

  /// Destination node name.
  final String toNode;

  /// Optional route value.
  final Object? route;
}

/// Node-based workflow agent.
class Workflow extends BaseAgent {
  /// Creates a workflow.
  Workflow({
    required super.name,
    super.description,
    required List<BaseNode> nodes,
    List<Edge> edges = const <Edge>[],
    this.maxConcurrency,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  }) : nodes = List<BaseNode>.unmodifiable(nodes),
       edges = List<Edge>.unmodifiable(edges),
       super(subAgents: const <BaseAgent>[]) {
    _validateNoStaticTaskModeNodes(this.nodes);
    _validateStaticGraphEdges(this.nodes, this.edges);
  }

  /// Nodes in this workflow.
  final List<BaseNode> nodes;

  /// Directed edges between nodes.
  final List<Edge> edges;

  /// Maximum number of graph-scheduled nodes to run at once.
  ///
  /// A null or non-positive value means unlimited concurrency. Dynamic child
  /// nodes run through [WorkflowContext.runNode] are not limited by this value.
  final int? maxConcurrency;

  /// Runs the workflow without requiring an ADK [InvocationContext].
  ///
  /// When [previousResult] and [resumeInputs] are provided, completed nodes from
  /// the previous run are reused and waiting nodes whose interrupt ids are
  /// resolved by [resumeInputs] are rerun with `context.resumeInputs`.
  Future<WorkflowResult> runWorkflow({
    Object? input,
    Map<String, Object?>? resumeInputs,
    WorkflowResult? previousResult,
  }) async {
    final WorkflowContext context = WorkflowContext(
      input: input,
      outputs: previousResult == null
          ? null
          : Map<String, Object?>.from(previousResult.outputs),
      nodeStates: previousResult == null
          ? null
          : _copyNodeStates(previousResult.nodeStates),
      resumeInputs: resumeInputs,
    );
    await _execute(context);
    return WorkflowResult(
      outputs: Map<String, Object?>.from(context.outputs),
      nodeStates: Map<String, NodeState>.from(context.nodeStates),
    );
  }

  /// Reconstructs a [WorkflowResult] from previously emitted workflow [events].
  ///
  /// The returned result can be passed to [runWorkflow] as `previousResult`.
  /// This mirrors the Python workflow rehydration path: completed node outputs,
  /// routes, waiting request-input interrupts, and user function responses are
  /// recovered from stored session events.
  WorkflowResult rehydrateResultFromEvents(
    Iterable<Event> events, {
    String? invocationId,
  }) {
    final Map<String, BaseNode> byName = <String, BaseNode>{
      for (final BaseNode node in nodes) node.name: node,
    };
    return _workflowResultFromEvents(
      events,
      workflowName: name,
      staticNodes: byName,
      invocationId: invocationId,
    );
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final WorkflowResult? previousResult = _rehydratedResultForContext(
      this,
      context,
    );
    final WorkflowContext workflowContext = WorkflowContext(
      invocationContext: context,
      input: context.userContent,
      outputs: previousResult == null
          ? null
          : Map<String, Object?>.from(previousResult.outputs),
      nodeStates: previousResult == null
          ? null
          : _copyNodeStates(previousResult.nodeStates),
    );
    await _execute(workflowContext);
    for (final MapEntry<String, Object?> entry
        in workflowContext.outputs.entries) {
      final List<Event>? nodeEvents = workflowContext._nodeEvents[entry.key];
      if (nodeEvents != null) {
        for (final Event event in nodeEvents) {
          yield event;
        }
        continue;
      }
      if (_isPreviouslyCompletedOutput(previousResult, entry.key)) {
        continue;
      }
      final Object? eventOutput =
          workflowContext._nodeOutputEvents[entry.key] ?? entry.value;
      final Event? event = _eventFromOutput(
        context,
        entry.key,
        eventOutput,
        state: workflowContext.nodeStates[entry.key],
      );
      if (event != null) {
        yield event;
      }
    }
  }

  Future<void> _execute(WorkflowContext context) async {
    final Map<String, BaseNode> byName = <String, BaseNode>{
      for (final BaseNode node in nodes) node.name: node,
    };
    if (byName.length != nodes.length) {
      throw ArgumentError('Workflow node names must be unique.');
    }

    final Map<String, Set<String>> dependencies = _dependencies(byName);
    _seedResumeInputs(context, byName);
    final Set<String> completed = <String>{
      for (final MapEntry<String, NodeState> entry
          in context.nodeStates.entries)
        if (_isCompletedNodeState(entry.value) && byName.containsKey(entry.key))
          entry.key,
    };
    final Set<String> pending = <String>{
      for (final String name in byName.keys)
        if (!completed.contains(name) &&
            !_hasUnresolvedWaitingInterrupts(context.nodeStates[name]))
          name,
    };
    final Set<String> active = edges.isEmpty
        ? byName.keys.toSet()
        : _initialActiveNodes(byName);
    for (final String completedNode in completed) {
      final Set<String> activatedTargets = _activateDownstream(
        fromNode: completedNode,
        route: context.nodeStates[completedNode]?.route,
        active: active,
      );
      if (activatedTargets.isEmpty) {
        _markTerminalOutputOwner(context, completedNode);
      }
    }

    final int? concurrencyLimit = maxConcurrency;
    if (concurrencyLimit != null && concurrencyLimit > 0) {
      await _executeWithConcurrencyLimit(
        context: context,
        byName: byName,
        dependencies: dependencies,
        pending: pending,
        completed: completed,
        active: active,
        concurrencyLimit: concurrencyLimit,
      );
      _validateSingleTerminalOutput(
        context,
        _terminalNodeNames(dependencies),
        workflowName: name,
      );
      return;
    }

    while (pending.any(active.contains)) {
      final List<String> ready = pending.where(active.contains).where((
        String name,
      ) {
        return dependencies[name]!.every(completed.contains);
      }).toList()..sort();
      if (ready.isEmpty) {
        throw StateError(
          'Workflow graph has unresolved or cyclic dependencies.',
        );
      }

      late final List<_NodeRunResult> results;
      try {
        results = await Future.wait(
          ready.map(
            (String name) => _runReadyNode(
              context: context,
              byName: byName,
              dependencies: dependencies,
              name: name,
            ),
          ),
          eagerError: true,
        );
      } catch (error, stackTrace) {
        context._cancel(error);
        Error.throwWithStackTrace(error, stackTrace);
      }

      for (final _NodeRunResult result in results) {
        pending.remove(result.name);
        final bool completedNode = _recordNodeResult(context, result);
        if (!completedNode) {
          continue;
        }
        completed.add(result.name);
        final Set<String> activatedTargets = _activateDownstream(
          fromNode: result.name,
          route: result.route,
          active: active,
        );
        if (activatedTargets.isEmpty) {
          _markTerminalOutputOwner(context, result.name);
        }
      }
    }
    _validateSingleTerminalOutput(
      context,
      _terminalNodeNames(dependencies),
      workflowName: name,
    );
  }

  Future<void> _executeWithConcurrencyLimit({
    required WorkflowContext context,
    required Map<String, BaseNode> byName,
    required Map<String, Set<String>> dependencies,
    required Set<String> pending,
    required Set<String> completed,
    required Set<String> active,
    required int concurrencyLimit,
  }) async {
    final Map<String, Future<_NodeRunResult>> running =
        <String, Future<_NodeRunResult>>{};
    while (pending.any(active.contains) || running.isNotEmpty) {
      final int availableSlots = concurrencyLimit - running.length;
      if (availableSlots > 0) {
        final List<String> ready = pending.where(active.contains).where((
          String name,
        ) {
          return dependencies[name]!.every(completed.contains);
        }).toList()..sort();
        if (ready.isEmpty && running.isEmpty && pending.any(active.contains)) {
          throw StateError(
            'Workflow graph has unresolved or cyclic dependencies.',
          );
        }
        for (final String name in ready.take(availableSlots)) {
          pending.remove(name);
          running[name] = _runReadyNode(
            context: context,
            byName: byName,
            dependencies: dependencies,
            name: name,
          );
        }
      }
      if (running.isEmpty) {
        break;
      }

      late final _NodeRunResult result;
      try {
        result = await Future.any(running.values);
      } catch (error, stackTrace) {
        context._cancel(error);
        Error.throwWithStackTrace(error, stackTrace);
      }
      running.remove(result.name);
      final bool completedNode = _recordNodeResult(context, result);
      if (!completedNode) {
        continue;
      }
      completed.add(result.name);
      final Set<String> activatedTargets = _activateDownstream(
        fromNode: result.name,
        route: result.route,
        active: active,
      );
      if (activatedTargets.isEmpty) {
        _markTerminalOutputOwner(context, result.name);
      }
    }
  }

  Future<_NodeRunResult> _runReadyNode({
    required WorkflowContext context,
    required Map<String, BaseNode> byName,
    required Map<String, Set<String>> dependencies,
    required String name,
  }) async {
    final BaseNode node = byName[name]!;
    final Object? nodeInput = _nodeInput(
      context: context,
      dependencies: dependencies[name]!,
    );
    final NodeState? state = context.nodeStates[name];
    final WorkflowContext nodeContext = context._childExecutionContext(
      resumeInputs: state?.resumeInputs.isNotEmpty == true
          ? Map<String, Object?>.from(state!.resumeInputs)
          : const <String, Object?>{},
    );
    final Object? output = await _runNodeWithRetry(
      context: nodeContext,
      node: node,
      nodeInput: nodeInput,
    );
    return _resultFromRawNodeOutput(node, output, context: nodeContext);
  }

  void _seedResumeInputs(
    WorkflowContext context,
    Map<String, BaseNode> byName,
  ) {
    if (context.resumeInputs.isEmpty) {
      return;
    }
    for (final MapEntry<String, NodeState> entry
        in context.nodeStates.entries) {
      final BaseNode? node = byName[entry.key];
      if (node == null) {
        continue;
      }
      final NodeState state = entry.value;
      if (state.status != NodeStatus.waiting || state.interrupts.isEmpty) {
        continue;
      }
      if (!_seedNodeResumeInputs(state, context.resumeInputs)) {
        continue;
      }
      if (state.interrupts.isEmpty && !node.rerunOnResume) {
        context.outputs[entry.key] = _outputFromResumeInputs(
          state.resumeInputs,
        );
        state.status = NodeStatus.completed;
        state.resumeInputs.clear();
      }
    }
  }

  Map<String, Set<String>> _dependencies(Map<String, BaseNode> byName) {
    final Map<String, Set<String>> dependencies = <String, Set<String>>{
      for (final BaseNode node in nodes) node.name: node.dependsOn.toSet(),
    };
    for (final Edge edge in edges) {
      if (!byName.containsKey(edge.toNode)) {
        throw ArgumentError('Unknown workflow edge target: ${edge.toNode}');
      }
      _validateChatModeEdge(edge, byName);
      if (edge.fromNode == START) {
        continue;
      }
      if (!byName.containsKey(edge.fromNode)) {
        throw ArgumentError('Unknown workflow edge source: ${edge.fromNode}');
      }
      dependencies[edge.toNode]!.add(edge.fromNode);
    }
    return dependencies;
  }

  Set<String> _initialActiveNodes(Map<String, BaseNode> byName) {
    final Set<String> targets = <String>{};
    final Set<String> startTargets = <String>{};
    for (final Edge edge in edges) {
      targets.add(edge.toNode);
      if (edge.fromNode == START) {
        startTargets.add(edge.toNode);
      }
    }
    return <String>{
      for (final BaseNode node in byName.values)
        if (!targets.contains(node.name) || startTargets.contains(node.name))
          node.name,
    };
  }

  Set<String> _terminalNodeNames(Map<String, Set<String>> dependencies) {
    final Set<String> nonTerminal = <String>{};
    for (final Edge edge in edges) {
      if (edge.fromNode != START) {
        nonTerminal.add(edge.fromNode);
      }
    }
    for (final Set<String> nodeDependencies in dependencies.values) {
      nonTerminal.addAll(nodeDependencies);
    }
    return <String>{
      for (final BaseNode node in nodes)
        if (!nonTerminal.contains(node.name)) node.name,
    };
  }

  Set<String> _activateDownstream({
    required String fromNode,
    required Object? route,
    required Set<String> active,
  }) {
    bool matchedSpecificRoute = false;
    final List<String> defaultTargets = <String>[];
    final Set<String> activatedTargets = <String>{};
    for (final Edge edge in edges.where(
      (Edge edge) => edge.fromNode == fromNode,
    )) {
      if (edge.route == null) {
        activatedTargets.add(edge.toNode);
        continue;
      }
      if (edge.route == DEFAULT_ROUTE) {
        defaultTargets.add(edge.toNode);
        continue;
      }
      if (_routeMatches(edge.route, route)) {
        matchedSpecificRoute = true;
        activatedTargets.add(edge.toNode);
      }
    }
    if (!matchedSpecificRoute) {
      activatedTargets.addAll(defaultTargets);
    }
    active.addAll(activatedTargets);
    return activatedTargets;
  }

  Object? _nodeInput({
    required WorkflowContext context,
    required Set<String> dependencies,
  }) {
    if (dependencies.isEmpty) {
      return context.input;
    }
    if (dependencies.length == 1) {
      return context.outputs[dependencies.single];
    }
    return <String, Object?>{
      for (final String dependency in dependencies)
        dependency: context.outputs[dependency],
    };
  }

  Event? _eventFromOutput(
    InvocationContext context,
    String author,
    Object? output, {
    NodeState? state,
  }) {
    if (output == null) {
      return null;
    }
    final NodeInfo nodeInfo = _nodeInfoForOutput(
      context,
      author,
      outputForKeys: state?.outputFor,
    );
    if (output is Event) {
      final Event event = output.nodeInfo.isEmpty
          ? output.copyWith(nodeInfo: nodeInfo)
          : output;
      return event.branch == null
          ? event.copyWith(branch: state?.branch ?? context.branch)
          : event;
    }
    if (output is RequestInput) {
      final Event event = createRequestInputEvent(
        output,
        invocationId: context.invocationId,
        author: author,
      );
      return event.copyWith(
        actions: state?.route == null
            ? event.actions
            : event.actions.copyWith(route: state?.route),
        nodeInfo: nodeInfo,
        branch: state?.branch ?? context.branch,
      );
    }
    if (output is Content) {
      return Event(
        invocationId: context.invocationId,
        author: author,
        branch: state?.branch ?? context.branch,
        nodeInfo: nodeInfo.copyWith(messageAsOutput: true),
        content: output,
      );
    }
    final String text = output is String ? output : jsonEncode(output);
    return Event(
      invocationId: context.invocationId,
      author: author,
      branch: state?.branch ?? context.branch,
      nodeInfo: nodeInfo.copyWith(messageAsOutput: true),
      content: Content.modelText(text),
    );
  }
}

WorkflowResult? _rehydratedResultForContext(
  Workflow workflow,
  InvocationContext context,
) {
  if (!context.isResumable) {
    return null;
  }
  final bool hasWorkflowEvents = context.session.events.any((Event event) {
    return event.invocationId == context.invocationId &&
        _isWorkflowNodePath(event.nodeInfo.path, _workflowRootPath(workflow));
  });
  if (!hasWorkflowEvents) {
    return null;
  }
  return workflow.rehydrateResultFromEvents(
    context.session.events,
    invocationId: context.invocationId,
  );
}

String _workflowRootPath(Workflow workflow) {
  final String workflowName = workflow.name.isEmpty
      ? 'workflow'
      : workflow.name;
  return '$workflowName@1';
}

bool _isPreviouslyCompletedOutput(WorkflowResult? previousResult, String key) {
  if (previousResult == null || !previousResult.outputs.containsKey(key)) {
    return false;
  }
  final NodeState? previousState = previousResult.nodeStates[key];
  return previousState != null && _isCompletedNodeState(previousState);
}

Event _rewriteNestedWorkflowEvent(
  Event event, {
  required Workflow nestedWorkflow,
  required String ownerPath,
}) {
  final String nestedRootPath = _workflowRootPath(nestedWorkflow);
  return event.copyWith(
    nodeInfo: _rewriteNestedWorkflowNodeInfo(
      event.nodeInfo,
      nestedRootPath: nestedRootPath,
      ownerPath: ownerPath,
    ),
  );
}

NodeInfo _rewriteNestedWorkflowNodeInfo(
  NodeInfo nodeInfo, {
  required String nestedRootPath,
  required String ownerPath,
}) {
  return nodeInfo.copyWith(
    path: _rewriteNestedWorkflowPath(
      nodeInfo.path,
      nestedRootPath: nestedRootPath,
      ownerPath: ownerPath,
    ),
    outputFor: nodeInfo.outputFor
        ?.map(
          (String path) => _rewriteNestedWorkflowPath(
            path,
            nestedRootPath: nestedRootPath,
            ownerPath: ownerPath,
          ),
        )
        .toList(growable: false),
  );
}

String _rewriteNestedWorkflowPath(
  String path, {
  required String nestedRootPath,
  required String ownerPath,
}) {
  if (path == nestedRootPath) {
    return ownerPath;
  }
  if (path.startsWith('$nestedRootPath/')) {
    return '$ownerPath/${path.substring(nestedRootPath.length + 1)}';
  }
  return path;
}

void _validateNoStaticTaskModeNodes(Iterable<BaseNode> nodes) {
  for (final BaseNode node in nodes) {
    final LlmAgent? agent = _taskModeAgentInStaticNode(node);
    if (agent == null) {
      continue;
    }
    throw ArgumentError(
      "Agent '${agent.name}' has mode='task' and cannot be used as a "
      'static workflow graph node. Use a chat coordinator with task '
      'sub-agents, or dispatch dynamically via WorkflowContext.runNode.',
    );
  }
}

LlmAgent? _taskModeAgentInStaticNode(BaseNode node) {
  if (node is AgentNode && node.agent is LlmAgent) {
    final LlmAgent agent = node.agent as LlmAgent;
    return agent.mode == 'task' ? agent : null;
  }
  if (node is ParallelWorker) {
    return _taskModeAgentInStaticNode(node.wrappedNode);
  }
  return null;
}

void _validateStaticGraphEdges(Iterable<BaseNode> nodes, Iterable<Edge> edges) {
  final Map<String, BaseNode> byName = <String, BaseNode>{
    for (final BaseNode node in nodes) node.name: node,
  };
  _validateNoDuplicateEdges(edges);
  _validateDefaultRoutes(edges);
  for (final Edge edge in edges) {
    _validateChatModeEdge(edge, byName);
  }
}

void _validateNoDuplicateEdges(Iterable<Edge> edges) {
  final Set<String> seen = <String>{};
  for (final Edge edge in edges) {
    final String key = '${edge.fromNode}\u0000${edge.toNode}';
    if (seen.add(key)) {
      continue;
    }
    throw ArgumentError(
      'Graph validation failed. Duplicate edge found: '
      'from=${edge.fromNode}, to=${edge.toNode}',
    );
  }
}

void _validateDefaultRoutes(Iterable<Edge> edges) {
  final Map<String, String> defaultRouteTargets = <String, String>{};
  for (final Edge edge in edges) {
    if (edge.route != DEFAULT_ROUTE) {
      continue;
    }
    final String? previousTarget = defaultRouteTargets[edge.fromNode];
    if (previousTarget == null) {
      defaultRouteTargets[edge.fromNode] = edge.toNode;
      continue;
    }
    throw ArgumentError(
      'Graph validation failed. Multiple DEFAULT_ROUTE edges found from '
      'node ${edge.fromNode} to $previousTarget and ${edge.toNode}',
    );
  }
}

void _validateChatModeEdge(Edge edge, Map<String, BaseNode> byName) {
  if (edge.fromNode == START) {
    return;
  }
  final BaseNode? toNode = byName[edge.toNode];
  if (toNode == null) {
    return;
  }
  final LlmAgent? agent = _chatModeAgentInNode(toNode);
  if (agent == null) {
    return;
  }
  throw ArgumentError(
    "The agent '${agent.name}' has been added to the workflow with "
    "mode='chat' following node '${edge.fromNode}'. This is not supported "
    'because chat-mode agents rely on conversational history and cannot '
    'consume direct node inputs from preceding nodes. Please change the '
    "agent's mode to 'single_turn'.",
  );
}

LlmAgent? _chatModeAgentInNode(BaseNode node) {
  if (node is AgentNode && node.agent is LlmAgent) {
    final LlmAgent agent = node.agent as LlmAgent;
    return agent.mode == 'chat' ? agent : null;
  }
  return null;
}

class _NodeRunResult {
  _NodeRunResult({
    required this.name,
    required this.output,
    this.route,
    Map<String, Object?>? stateDelta,
    this.eventOutput,
    Set<String>? interruptIds,
    this.waiting = false,
  }) : stateDelta = stateDelta ?? <String, Object?>{},
       interruptIds = interruptIds ?? <String>{};

  final String name;
  final Object? output;
  final Object? route;
  final Map<String, Object?> stateDelta;
  final Event? eventOutput;
  final Set<String> interruptIds;
  final bool waiting;
}

Future<Object?> _runNodeWithRetry({
  required WorkflowContext context,
  required BaseNode node,
  required Object? nodeInput,
  String? stateKey,
  String? runId,
}) async {
  final RetryConfig? retry = node.retryConfig;
  _validateRetryExceptionFilters(retry);
  final int maxAttempts = retry == null
      ? 1
      : (retry.maxAttempts < 1 ? 1 : retry.maxAttempts);
  final String key = stateKey ?? node.name;
  final NodeState state = context.nodeStates.putIfAbsent(key, NodeState.new);
  context._currentNodeKey = key;
  context._currentNodeRerunOnResume = node.rerunOnResume;
  state.input = nodeInput;
  if (state.status == NodeStatus.inactive || state.runId == null) {
    state.runCounter += 1;
    state.runId = runId ?? '${state.runCounter}';
  }

  Object? lastError;
  for (int attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      context.throwIfCancelled();
    } on AdkAbortException catch (error) {
      state.status = NodeStatus.cancelled;
      state.error = error;
      rethrow;
    }
    state.status = NodeStatus.running;
    state.attemptCount = attempt;
    try {
      Future<Object?> future = Future<Object?>.sync(
        () => node.run(context, nodeInput),
      );
      final Duration? timeout = node.timeout;
      if (timeout != null) {
        future = future.timeout(
          timeout,
          onTimeout: () =>
              throw NodeTimeoutError(nodeName: node.name, timeout: timeout),
        );
      }
      final Object? output = await future;
      try {
        context.throwIfCancelled();
      } on AdkAbortException catch (error) {
        state.status = NodeStatus.cancelled;
        state.error = error;
        rethrow;
      }
      if (_hasReturnedWorkflowOutput(output) &&
          context._hasDirectOutput &&
          !context._outputDelegated) {
        throw StateError(
          'Workflow node `${node.name}` produced both a return output and '
          'ctx.output.',
        );
      }
      if (_routeFromOutput(output) != null && context.route != null) {
        throw StateError(
          'Workflow node `${node.name}` produced both a return route and '
          'ctx.route.',
        );
      }
      state.status = NodeStatus.completed;
      state.error = null;
      return output;
    } on AdkAbortException catch (error) {
      state.status = NodeStatus.cancelled;
      state.error = error;
      rethrow;
    } catch (error) {
      lastError = error;
      state.status = NodeStatus.failed;
      state.error = error;
      if (attempt >= maxAttempts || !_shouldRetryError(error, retry)) {
        rethrow;
      }
      await Future<void>.delayed(_retryDelay(retry!, attempt));
    }
  }
  throw StateError('Workflow node failed unexpectedly: $lastError');
}

void _validateRetryExceptionFilters(RetryConfig? retry) {
  final List<Object>? filters = retry?.exceptions;
  if (filters == null) {
    return;
  }
  for (final Object filter in filters) {
    if (filter is String || filter is Type) {
      continue;
    }
    throw ArgumentError.value(
      filter,
      'exceptions',
      'RetryConfig.exceptions must contain exception class names (String) '
          'or exception classes (Type).',
    );
  }
}

bool _shouldRetryError(Object error, RetryConfig? retry) {
  if (retry == null) {
    return false;
  }
  final List<Object>? filters = retry.exceptions;
  if (filters == null) {
    return true;
  }
  if (filters.isEmpty) {
    return false;
  }

  final String errorTypeName = error.runtimeType.toString();
  for (final Object filter in filters) {
    if (filter is String && filter == errorTypeName) {
      return true;
    }
    if (filter is Type &&
        (filter == error.runtimeType || filter.toString() == errorTypeName)) {
      return true;
    }
  }
  return false;
}

Duration _retryDelay(RetryConfig retry, int attempt) {
  if (retry.initialDelay == Duration.zero) {
    return Duration.zero;
  }
  final double factor = retry.backoffMultiplier <= 0
      ? 1
      : retry.backoffMultiplier;
  int delayMs = retry.initialDelay.inMilliseconds;
  for (int i = 1; i < attempt; i += 1) {
    delayMs = (delayMs * factor).round();
  }
  if (delayMs > retry.maxDelay.inMilliseconds) {
    delayMs = retry.maxDelay.inMilliseconds;
  }
  if (retry.jitter > 0 && delayMs > 0) {
    final double spread = delayMs * retry.jitter;
    final double offset = (math.Random().nextDouble() * spread * 2) - spread;
    delayMs = math.max(0, delayMs + offset).round();
  }
  return Duration(milliseconds: delayMs);
}

_NodeRunResult _resultFromRawNodeOutput(
  BaseNode node,
  Object? rawOutput, {
  WorkflowContext? context,
  String? name,
}) {
  final bool outputDelegated = context?._outputDelegated == true;
  final Object? workflowOutput = outputDelegated
      ? null
      : context?._hasDirectOutput == true
      ? context!._directOutput
      : _workflowOutputFromRaw(rawOutput);
  final Object? route = _routeFromOutput(rawOutput) ?? context?.route;
  final bool hasOutput =
      outputDelegated ||
      context?._hasDirectOutput == true ||
      _hasWorkflowOutput(rawOutput);
  final Map<String, Object?> stateDelta = <String, Object?>{
    ..._stateDeltaFromOutput(rawOutput),
    if (context?._hasDirectOutput == true)
      ..._stateDeltaFromOutput(context!._directOutput),
  };
  final Event? eventOutput = _eventOutputFromRaw(rawOutput, context);
  return _NodeRunResult(
    name: name ?? node.name,
    output: workflowOutput,
    route: route,
    stateDelta: stateDelta,
    eventOutput: eventOutput,
    interruptIds: <String>{
      ..._interruptIdsFromOutput(rawOutput),
      ...?context?.interruptIds,
    },
    waiting: node.waitForOutput && !hasOutput && route == null,
  );
}

bool _recordNodeResult(WorkflowContext context, _NodeRunResult result) {
  final NodeState? state = context.nodeStates[result.name];
  final Session? session = context.invocationContext?.session;
  if (session != null) {
    _mergeStateDelta(session, result.stateDelta);
  }
  if (result.eventOutput != null) {
    context._nodeOutputEvents[result.name] = result.eventOutput!;
  } else {
    context._nodeOutputEvents.remove(result.name);
  }
  if (state != null) {
    state.route = result.route;
  }
  if (result.output != null || result.route != null) {
    context.outputs[result.name] = result.output;
  }
  if (result.interruptIds.isNotEmpty || result.waiting) {
    if (state != null) {
      state.status = NodeStatus.waiting;
      state.interrupts
        ..clear()
        ..addAll(result.interruptIds);
    }
    return false;
  }
  context.outputs[result.name] = result.output;
  if (state != null) {
    state.interrupts.clear();
    state.resumeInputs.clear();
  }
  return true;
}

void _markTerminalOutputOwner(WorkflowContext context, String nodeName) {
  if (!context.outputs.containsKey(nodeName)) {
    return;
  }
  final NodeState? state = context.nodeStates[nodeName];
  if (state == null) {
    return;
  }
  _addOutputOwner(state.outputFor, nodeName);
  _addOutputOwner(state.outputFor, _workflowOutputOwner);
  for (final NodeState childState in context.nodeStates.values) {
    if (identical(childState, state)) {
      continue;
    }
    if (childState.outputFor.contains(nodeName)) {
      _addOutputOwner(childState.outputFor, _workflowOutputOwner);
    }
  }
}

void _validateSingleTerminalOutput(
  WorkflowContext context,
  Set<String> terminalNodeNames, {
  required String workflowName,
}) {
  final List<String> terminalOutputs = <String>[
    for (final String nodeName in terminalNodeNames)
      if (context.outputs.containsKey(nodeName)) nodeName,
  ];
  if (terminalOutputs.length <= 1) {
    return;
  }
  throw StateError(
    'Workflow $workflowName: multiple terminal nodes produced output '
    '(${terminalOutputs.length}). A workflow must have at most one terminal '
    'output.',
  );
}

void _addOutputOwner(List<String> outputFor, String owner) {
  if (!outputFor.contains(owner)) {
    outputFor.add(owner);
  }
}

bool _seedNodeResumeInputs(NodeState state, Map<String, Object?> resumeInputs) {
  if (state.status != NodeStatus.waiting ||
      state.interrupts.isEmpty ||
      resumeInputs.isEmpty) {
    return false;
  }
  final Map<String, Object?> resolved = <String, Object?>{
    for (final String interruptId in state.interrupts)
      if (resumeInputs.containsKey(interruptId))
        interruptId: resumeInputs[interruptId],
  };
  if (resolved.isEmpty) {
    return false;
  }
  state.resumeInputs.addAll(resolved);
  state.interrupts.removeWhere(resolved.containsKey);
  return true;
}

WorkflowResult _workflowResultFromEvents(
  Iterable<Event> events, {
  required String workflowName,
  required Map<String, BaseNode> staticNodes,
  String? invocationId,
}) {
  final String effectiveWorkflowName = workflowName.isEmpty
      ? 'workflow'
      : workflowName;
  final String workflowPath = '$effectiveWorkflowName@1';
  final Map<String, Object?> outputs = <String, Object?>{};
  final Map<String, NodeState> states = <String, NodeState>{};
  final Map<String, String> interruptOwner = <String, String>{};
  final Map<String, Object?> responseSchemas = <String, Object?>{};

  NodeState stateFor(String key, String? runId, String? parentRunId) {
    return states.putIfAbsent(
      key,
      () => NodeState(
        status: NodeStatus.inactive,
        runId: runId,
        runCounter: _runCounterFromRunId(runId),
        parentRunId: parentRunId,
      ),
    );
  }

  for (final Event event in events) {
    if (invocationId != null && event.invocationId != invocationId) {
      continue;
    }

    if (event.author == 'user' && event.getFunctionResponses().isNotEmpty) {
      _applyWorkflowResumeResponses(
        event,
        states: states,
        outputs: outputs,
        staticNodes: staticNodes,
        interruptOwner: interruptOwner,
        responseSchemas: responseSchemas,
      );
      continue;
    }

    final String path = event.nodeInfo.path;
    if (!_isWorkflowNodePath(path, workflowPath)) {
      continue;
    }

    final _WorkflowEventOwner? owner = _workflowEventOwnerForPath(
      path,
      workflowPath: workflowPath,
      staticNodes: staticNodes,
    );
    if (owner == null) {
      continue;
    }

    final NodeState state = stateFor(owner.key, owner.runId, owner.parentRunId);
    if (event.branch != null) {
      state.branch = event.branch;
    }
    final List<String>? outputFor = _outputKeysFromPaths(
      event.nodeInfo.outputFor,
      workflowPath: workflowPath,
      staticNodes: staticNodes,
    );
    if (outputFor != null) {
      state.outputFor
        ..clear()
        ..addAll(outputFor);
    }

    final Object? route = event.actions.route;
    final bool hasRoute = route != null;
    if (hasRoute) {
      state.route = route;
      if (state.status != NodeStatus.waiting) {
        state.status = NodeStatus.completed;
      }
    }

    final Object? eventOutput = _workflowOutputFromEvent(event);
    final bool hasOutput = event.hasOutput || _hasMessageAsOutput(event);
    if (hasOutput) {
      outputs[owner.key] = eventOutput;
      if (state.status != NodeStatus.waiting) {
        state.status = NodeStatus.completed;
      }
    }

    final bool hasError = event.errorCode != null;
    if (hasError) {
      state.status = NodeStatus.failed;
      state.error = event.errorMessage ?? event.errorCode;
    }

    final Set<String> interruptIds = _interruptIdsFromEvent(event);
    if (interruptIds.isEmpty) {
      if (!hasOutput &&
          !hasRoute &&
          !hasError &&
          state.status != NodeStatus.waiting) {
        state.status = NodeStatus.completed;
      }
      continue;
    }

    final RequestInput? requestInput = _requestInputFromEvent(event);
    if (requestInput != null) {
      outputs[owner.key] = requestInput;
    }
    state.status = NodeStatus.waiting;
    state.interrupts
      ..clear()
      ..addAll(interruptIds);
    for (final String interruptId in interruptIds) {
      interruptOwner[interruptId] = owner.key;
      final Object? schema = _responseSchemaFromEvent(event, interruptId);
      if (schema != null) {
        responseSchemas[interruptId] = schema;
      }
    }
  }

  return WorkflowResult(outputs: outputs, nodeStates: states);
}

void _applyWorkflowResumeResponses(
  Event event, {
  required Map<String, NodeState> states,
  required Map<String, Object?> outputs,
  required Map<String, BaseNode> staticNodes,
  required Map<String, String> interruptOwner,
  required Map<String, Object?> responseSchemas,
}) {
  for (final FunctionResponse response in event.getFunctionResponses()) {
    final String? interruptId = response.id;
    if (interruptId == null) {
      continue;
    }
    final String? ownerKey = interruptOwner[interruptId];
    if (ownerKey == null) {
      continue;
    }
    final NodeState state = states.putIfAbsent(
      ownerKey,
      () => NodeState(status: NodeStatus.waiting),
    );
    Object? responseData = _unwrapWorkflowResumeResponse(response.response);
    responseData = _validateWorkflowResumeResponse(
      responseData,
      responseSchemas[interruptId],
    );
    state.resumeInputs[interruptId] = responseData;
    state.interrupts.remove(interruptId);
    if (state.interrupts.isNotEmpty) {
      state.status = NodeStatus.waiting;
      continue;
    }

    final BaseNode? staticNode = staticNodes[ownerKey];
    if (staticNode != null && !staticNode.rerunOnResume) {
      outputs[ownerKey] = _outputFromResumeInputs(state.resumeInputs);
      state.status = NodeStatus.completed;
      state.resumeInputs.clear();
    } else {
      state.status = NodeStatus.waiting;
    }
  }
}

class _WorkflowEventOwner {
  _WorkflowEventOwner({
    required this.key,
    required this.runId,
    required this.parentRunId,
  });

  final String key;
  final String? runId;
  final String? parentRunId;
}

_WorkflowEventOwner? _workflowEventOwnerForPath(
  String path, {
  required String workflowPath,
  required Map<String, BaseNode> staticNodes,
}) {
  final List<String> segments = _workflowPathSegments(path);
  if (segments.length < 2 || segments.first != workflowPath) {
    return null;
  }
  final String leaf = segments.last;
  final String nodeName = _workflowNodeNameFromSegment(leaf);
  if (nodeName.isEmpty) {
    return null;
  }
  final bool staticNode =
      segments.length == 2 && staticNodes.containsKey(nodeName);
  return _WorkflowEventOwner(
    key: staticNode ? nodeName : leaf,
    runId: _workflowRunIdFromSegment(leaf),
    parentRunId: segments.length < 2
        ? null
        : _workflowRunIdFromSegment(segments[segments.length - 2]),
  );
}

List<String>? _outputKeysFromPaths(
  List<String>? paths, {
  required String workflowPath,
  required Map<String, BaseNode> staticNodes,
}) {
  if (paths == null) {
    return null;
  }
  final List<String> keys = <String>[];
  for (final String path in paths) {
    if (path == workflowPath) {
      keys.add(_workflowOutputOwner);
      continue;
    }
    final _WorkflowEventOwner? owner = _workflowEventOwnerForPath(
      path,
      workflowPath: workflowPath,
      staticNodes: staticNodes,
    );
    if (owner != null) {
      keys.add(owner.key);
    }
  }
  return keys;
}

bool _isWorkflowNodePath(String path, String workflowPath) {
  final NodePathBuilder nodePath = NodePathBuilder.fromString(path);
  final NodePathBuilder workflowNodePath = NodePathBuilder.fromString(
    workflowPath,
  );
  return nodePath == workflowNodePath ||
      nodePath.isDescendantOf(workflowNodePath);
}

List<String> _workflowPathSegments(String path) {
  return NodePathBuilder.fromString(path).segments;
}

String _workflowNodeNameFromSegment(String segment) {
  return NodePathBuilder(<String>[segment]).nodeName;
}

String? _workflowRunIdFromSegment(String segment) {
  return NodePathBuilder(<String>[segment]).runId;
}

int _runCounterFromRunId(String? runId) {
  final int? parsed = runId == null ? null : int.tryParse(runId);
  return parsed == null || parsed < 0 ? 0 : parsed;
}

bool _hasMessageAsOutput(Event event) {
  return event.nodeInfo.messageAsOutput == true && event.content != null;
}

Object? _workflowOutputFromEvent(Event event) {
  if (event.hasOutput) {
    return event.output;
  }
  if (!_hasMessageAsOutput(event)) {
    return null;
  }
  return _outputFromAgentEvent(event);
}

Set<String> _interruptIdsFromEvent(Event event) {
  return <String>{
    ...?event.longRunningToolIds,
    ...getRequestInputInterruptIds(event),
  };
}

RequestInput? _requestInputFromEvent(Event event) {
  final List<FunctionCall> calls = event
      .getFunctionCalls()
      .where((FunctionCall call) => call.name == requestInputFunctionCallName)
      .toList(growable: false);
  if (calls.length != 1) {
    return null;
  }
  return RequestInput.fromJson(calls.single.args);
}

Object? _responseSchemaFromEvent(Event event, String interruptId) {
  for (final FunctionCall call in event.getFunctionCalls()) {
    if (call.name != requestInputFunctionCallName || call.id != interruptId) {
      continue;
    }
    return call.args['response_schema'] ?? call.args['responseSchema'];
  }
  return null;
}

Object? _unwrapWorkflowResumeResponse(Object? response) {
  if (response is Map &&
      response.length == 1 &&
      response.containsKey('result')) {
    final Object? value = response['result'];
    if (value is String) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
    return value;
  }
  return response;
}

Object? _validateWorkflowResumeResponse(Object? value, Object? schema) {
  if (schema is! Map) {
    return value;
  }
  final Object? type = schema['type'];
  switch (type) {
    case 'integer':
      return _coerceWorkflowInt(value);
    case 'number':
      return _coerceWorkflowNum(value);
    case 'string':
      return value is String ? value : '$value';
    case 'boolean':
      return _coerceWorkflowBool(value);
    case 'array':
      if (value is List) {
        return value;
      }
      throw ArgumentError.value(value, 'response', 'Expected array response.');
    case 'object':
      if (value is Map) {
        return <String, Object?>{
          for (final MapEntry<dynamic, dynamic> entry in value.entries)
            '${entry.key}': entry.value,
        };
      }
      throw ArgumentError.value(value, 'response', 'Expected object response.');
    default:
      return value;
  }
}

int _coerceWorkflowInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.toInt() == value) {
    return value.toInt();
  }
  if (value is String) {
    final int? parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw ArgumentError.value(value, 'response', 'Expected integer response.');
}

num _coerceWorkflowNum(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    final num? parsed = num.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw ArgumentError.value(value, 'response', 'Expected number response.');
}

bool _coerceWorkflowBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  throw ArgumentError.value(value, 'response', 'Expected boolean response.');
}

Map<String, NodeState> _copyNodeStates(Map<String, NodeState> states) {
  return <String, NodeState>{
    for (final MapEntry<String, NodeState> entry in states.entries)
      entry.key: NodeState(
        status: entry.value.status,
        input: entry.value.input,
        attemptCount: entry.value.attemptCount,
        interrupts: List<String>.from(entry.value.interrupts),
        resumeInputs: Map<String, Object?>.from(entry.value.resumeInputs),
        outputFor: List<String>.from(entry.value.outputFor),
        branch: entry.value.branch,
        runCounter: entry.value.runCounter,
        runId: entry.value.runId,
        parentRunId: entry.value.parentRunId,
        route: entry.value.route,
        error: entry.value.error,
      ),
  };
}

bool _isCompletedNodeState(NodeState state) {
  return state.status == NodeStatus.completed ||
      state.status == NodeStatus.succeeded;
}

bool _hasUnresolvedWaitingInterrupts(NodeState? state) {
  if (state == null || state.status != NodeStatus.waiting) {
    return false;
  }
  return state.interrupts.isNotEmpty;
}

Object? _outputFromResumeInputs(Map<String, Object?> resumeInputs) {
  if (resumeInputs.length == 1) {
    return resumeInputs.values.single;
  }
  return Map<String, Object?>.from(resumeInputs);
}

String _nodeName(Object node) {
  if (node is BaseNode) {
    return node.name;
  }
  return '$node';
}

Map<String, dynamic> _toolArgsFromInput(Object? nodeInput) {
  if (nodeInput == null) {
    return <String, dynamic>{};
  }
  if (nodeInput is Map) {
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in nodeInput.entries)
        '${entry.key}': entry.value,
    };
  }
  throw ArgumentError.value(
    nodeInput,
    'nodeInput',
    'ToolNode input must be a map of tool arguments or null.',
  );
}

InvocationContext _standaloneInvocationContext(String nodeName) {
  final InMemorySessionService sessionService = InMemorySessionService();
  return InvocationContext(
    sessionService: sessionService,
    invocationId: 'workflow_${nodeName}_tool',
    agent: LlmAgent(name: 'workflow_${nodeName}_tool_agent'),
    session: Session(
      id: 'workflow_${nodeName}_session',
      appName: 'workflow',
      userId: 'workflow',
    ),
  );
}

Content _contentFromNodeInput(Object nodeInput) {
  if (nodeInput is Content) {
    return nodeInput.copyWith(role: 'user');
  }
  if (nodeInput is String) {
    return Content.userText(nodeInput);
  }
  if (nodeInput is Map || nodeInput is List) {
    return Content.userText(jsonEncode(nodeInput));
  }
  return Content.userText('$nodeInput');
}

Object? _outputFromAgentEvent(Event event) {
  if (event.hasOutput) {
    return event.output;
  }
  final Content? content = event.content;
  if (content == null) {
    return null;
  }
  if (event.getFunctionCalls().isNotEmpty ||
      event.getFunctionResponses().isNotEmpty ||
      event.partial == true) {
    return event;
  }
  final String text = content.parts
      .where((Part part) => part.text != null && !part.thought)
      .map((Part part) => part.text!)
      .join();
  if (text.isNotEmpty ||
      content.parts.every((Part part) => part.text != null)) {
    return text;
  }
  return content;
}

void _mergeStateDelta(Session session, Map<String, Object?> stateDelta) {
  if (stateDelta.isEmpty) {
    return;
  }
  session.state.addAll(stateDelta);
}

Object? _routeFromOutput(Object? output) {
  if (output is Event) {
    return output.actions.route;
  }
  return null;
}

Map<String, Object?> _stateDeltaFromOutput(Object? output) {
  if (output is Event) {
    return output.actions.stateDelta;
  }
  return const <String, Object?>{};
}

Event? _eventOutputFromRaw(Object? rawOutput, WorkflowContext? context) {
  if (rawOutput is Event) {
    if (context?._hasDirectOutput == true &&
        !rawOutput.hasOutput &&
        rawOutput.content == null) {
      return rawOutput.copyWith(output: context!._directOutput);
    }
    return rawOutput;
  }
  final Object? directOutput = context?._directOutput;
  return directOutput is Event ? directOutput : null;
}

Object? _workflowOutputFromRaw(Object? output) {
  if (output is Event) {
    if (output.hasOutput) {
      return output.output;
    }
    if (output.content == null && output.actions.route != null) {
      return null;
    }
  }
  return output;
}

bool _hasWorkflowOutput(Object? output) {
  if (output is Event) {
    return output.hasOutput || output.content != null;
  }
  return output != null;
}

bool _hasReturnedWorkflowOutput(Object? output) {
  if (output is Event) {
    return output.hasOutput ||
        (output.nodeInfo.messageAsOutput == true && output.content != null);
  }
  return output != null;
}

Set<String> _interruptIdsFromOutput(Object? output) {
  if (output is RequestInput) {
    return <String>{output.interruptId};
  }
  if (output is Event) {
    return <String>{
      ...?output.longRunningToolIds,
      ...getRequestInputInterruptIds(output),
    };
  }
  return <String>{};
}

NodeInfo _nodeInfoForOutput(
  InvocationContext context,
  String outputKey, {
  List<String>? outputForKeys,
}) {
  final String nodePath = _nodePathForOutputKey(context, outputKey);
  final List<String> outputFor = outputForKeys == null || outputForKeys.isEmpty
      ? <String>[nodePath]
      : outputForKeys
            .map((String key) => _nodePathForOutputKey(context, key))
            .toList();
  return NodeInfo(path: nodePath, outputFor: outputFor);
}

String _nodePathForOutputKey(InvocationContext context, String outputKey) {
  final String workflowName = context.agent.name.isEmpty
      ? 'workflow'
      : context.agent.name;
  if (outputKey == _workflowOutputOwner) {
    return '$workflowName@1';
  }
  final int separator = outputKey.lastIndexOf('@');
  if (separator > 0 && separator < outputKey.length - 1) {
    final String nodeName = outputKey.substring(0, separator);
    final String runId = outputKey.substring(separator + 1);
    return '$workflowName@1/$nodeName@$runId';
  }
  return '$workflowName@1/$outputKey@1';
}

bool _routeMatches(Object? edgeRoute, Object? emittedRoute) {
  final Set<Object?> edgeRoutes = _routeSet(edgeRoute);
  if (emittedRoute is Iterable && emittedRoute is! String) {
    return emittedRoute.any(edgeRoutes.contains);
  }
  return edgeRoutes.contains(emittedRoute);
}

Set<Object?> _routeSet(Object? route) {
  if (route is Iterable && route is! String) {
    return route.toSet();
  }
  return <Object?>{route};
}
