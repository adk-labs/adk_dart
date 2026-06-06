/// Experimental node-based workflow runtime.
library;

import 'dart:async';
import 'dart:convert';

import '../agents/base_agent.dart';
import '../agents/context.dart';
import '../agents/invocation_context.dart';
import '../agents/llm_agent.dart';
import '../events/event.dart';
import '../events/request_input.dart';
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

/// Function callback signature for [FunctionNode].
typedef WorkflowFunction =
    FutureOr<Object?> Function(WorkflowContext context, Object? nodeInput);

/// Retry configuration for workflow node execution.
class RetryConfig {
  /// Creates retry configuration.
  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = Duration.zero,
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2,
    this.exceptions,
  });

  /// Maximum number of attempts including the first run.
  ///
  /// This default applies only when a node explicitly sets [retryConfig].
  /// Nodes without retry config still run once.
  final int maxAttempts;

  /// Delay before the first retry.
  final Duration initialDelay;

  /// Maximum delay between retries.
  final Duration maxDelay;

  /// Exponential backoff multiplier.
  final double backoffMultiplier;

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
  }) : outputs = outputs ?? <String, Object?>{},
       nodeStates = nodeStates ?? <String, NodeState>{},
       resumeInputs = resumeInputs ?? <String, Object?>{};

  bool _hasDirectOutput = false;
  Object? _directOutput;
  bool _outputDelegated = false;
  final Map<String, int> _childRunCounters = <String, int>{};
  String? _currentNodeKey;
  bool? _currentNodeRerunOnResume;

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
    return WorkflowContext(
      invocationContext: invocationContext,
      input: input,
      outputs: outputs,
      nodeStates: nodeStates,
      resumeInputs: resumeInputs ?? this.resumeInputs,
    );
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
  RetryConfig? retryConfig,
  Duration? timeout,
}) {
  return ParallelWorker(
    node: nodeLike,
    maxConcurrency: maxConcurrency,
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
    RetryConfig? retryConfig,
    Duration? timeout,
  }) {
    final BaseNode wrappedNode = _buildParallelWorkerNode(node);
    return ParallelWorker._(
      wrappedNode: wrappedNode,
      maxConcurrency: maxConcurrency,
      retryConfig: retryConfig,
      timeout: timeout,
    );
  }

  ParallelWorker._({
    required this.wrappedNode,
    required this.maxConcurrency,
    super.retryConfig,
    super.timeout,
  }) : super(name: wrappedNode.name, rerunOnResume: true);

  /// Wrapped child node.
  final BaseNode wrappedNode;

  /// Maximum worker tasks to run at once. `null` means unlimited.
  final int? maxConcurrency;

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
    final int limit = maxConcurrency == null || maxConcurrency! <= 0
        ? items.length
        : maxConcurrency!;
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final int index = nextIndex;
        nextIndex += 1;
        if (index >= items.length) {
          return;
        }
        results[index] = await context.runNode(
          wrappedNode,
          input: items[index],
          useSubBranch: true,
        );
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = 0; i < limit && i < items.length; i += 1) worker(),
    ]);
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
    final InvocationContext parentContext =
        context.invocationContext ?? _standaloneInvocationContext(name);
    final Content? userContent = nodeInput == null
        ? null
        : _contentFromNodeInput(nodeInput);
    final InvocationContext agentContext = parentContext.copyWith(
      agent: agent,
      userContent: userContent,
    );

    Event? finalEvent;
    await for (final Event event in agent.runAsync(agentContext)) {
      if (event.isFinalResponse()) {
        finalEvent = event;
      }
    }

    if (finalEvent == null) {
      return null;
    }
    _mergeStateDelta(agentContext.session, finalEvent.actions.stateDelta);
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
    _validateNoChatModeAgentAfterNode(this.nodes, this.edges);
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

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final WorkflowContext workflowContext = WorkflowContext(
      invocationContext: context,
      input: context.userContent,
    );
    await _execute(workflowContext);
    for (final MapEntry<String, Object?> entry
        in workflowContext.outputs.entries) {
      final Event? event = _eventFromOutput(
        context,
        entry.key,
        entry.value,
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
      _activateDownstream(
        fromNode: completedNode,
        route: context.nodeStates[completedNode]?.route,
        active: active,
      );
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

      final List<_NodeRunResult> results = await Future.wait(
        ready.map(
          (String name) => _runReadyNode(
            context: context,
            byName: byName,
            dependencies: dependencies,
            name: name,
          ),
        ),
      );

      for (final _NodeRunResult result in results) {
        pending.remove(result.name);
        final bool completedNode = _recordNodeResult(context, result);
        if (!completedNode) {
          continue;
        }
        completed.add(result.name);
        _activateDownstream(
          fromNode: result.name,
          route: result.route,
          active: active,
        );
      }
    }
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

      final _NodeRunResult result = await Future.any(running.values);
      running.remove(result.name);
      final bool completedNode = _recordNodeResult(context, result);
      if (!completedNode) {
        continue;
      }
      completed.add(result.name);
      _activateDownstream(
        fromNode: result.name,
        route: result.route,
        active: active,
      );
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

  void _activateDownstream({
    required String fromNode,
    required Object? route,
    required Set<String> active,
  }) {
    bool matchedSpecificRoute = false;
    final List<String> defaultTargets = <String>[];
    for (final Edge edge in edges.where(
      (Edge edge) => edge.fromNode == fromNode,
    )) {
      if (edge.route == null) {
        active.add(edge.toNode);
        continue;
      }
      if (edge.route == DEFAULT_ROUTE) {
        defaultTargets.add(edge.toNode);
        continue;
      }
      if (_routeMatches(edge.route, route)) {
        matchedSpecificRoute = true;
        active.add(edge.toNode);
      }
    }
    if (!matchedSpecificRoute) {
      active.addAll(defaultTargets);
    }
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
      return createRequestInputEvent(
        output,
        invocationId: context.invocationId,
        author: author,
      ).copyWith(nodeInfo: nodeInfo, branch: state?.branch ?? context.branch);
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

void _validateNoChatModeAgentAfterNode(
  Iterable<BaseNode> nodes,
  Iterable<Edge> edges,
) {
  final Map<String, BaseNode> byName = <String, BaseNode>{
    for (final BaseNode node in nodes) node.name: node,
  };
  for (final Edge edge in edges) {
    _validateChatModeEdge(edge, byName);
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
    Set<String>? interruptIds,
    this.waiting = false,
  }) : interruptIds = interruptIds ?? <String>{};

  final String name;
  final Object? output;
  final Object? route;
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
  return _NodeRunResult(
    name: name ?? node.name,
    output: workflowOutput,
    route: route,
    interruptIds: <String>{
      ..._interruptIdsFromOutput(rawOutput),
      ...?context?.interruptIds,
    },
    waiting: node.waitForOutput && !hasOutput && route == null,
  );
}

bool _recordNodeResult(WorkflowContext context, _NodeRunResult result) {
  final NodeState? state = context.nodeStates[result.name];
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
