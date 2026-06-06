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
    this.runCounter = 0,
    this.runId,
    this.parentRunId,
    this.error,
  }) : interrupts = interrupts ?? <String>[],
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

  /// Sequential run counter for fresh node runs.
  int runCounter;

  /// Current node run identifier.
  String? runId;

  /// Parent dynamic node run identifier, when applicable.
  String? parentRunId;

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
  }) : outputs = outputs ?? <String, Object?>{},
       nodeStates = nodeStates ?? <String, NodeState>{};

  /// ADK invocation context when running as an agent.
  final InvocationContext? invocationContext;

  /// Initial workflow input.
  final Object? input;

  /// Node outputs keyed by node name.
  final Map<String, Object?> outputs;

  /// Node states keyed by node name.
  final Map<String, NodeState> nodeStates;

  /// Reads an output by node [name].
  Object? outputOf(String name) => outputs[name];
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
    return AgentNode(
      agent: nodeLike,
      name: name,
      description: description,
      dependsOn: dependsOn,
      rerunOnResume: rerunOnResume ?? false,
      waitForOutput: waitForOutput ?? false,
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
    super.rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
  }) : super(name: name ?? agent.name);

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
    super.beforeAgentCallback,
    super.afterAgentCallback,
  }) : nodes = List<BaseNode>.unmodifiable(nodes),
       edges = List<Edge>.unmodifiable(edges),
       super(subAgents: const <BaseAgent>[]);

  /// Nodes in this workflow.
  final List<BaseNode> nodes;

  /// Directed edges between nodes.
  final List<Edge> edges;

  /// Runs the workflow without requiring an ADK [InvocationContext].
  Future<WorkflowResult> runWorkflow({Object? input}) async {
    final WorkflowContext context = WorkflowContext(input: input);
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
      final Event? event = _eventFromOutput(context, entry.key, entry.value);
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
    final Set<String> pending = byName.keys.toSet();
    final Set<String> completed = <String>{};
    final Set<String> active = edges.isEmpty
        ? byName.keys.toSet()
        : _initialActiveNodes(byName);

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
        ready.map((String name) async {
          final BaseNode node = byName[name]!;
          final Object? nodeInput = _nodeInput(
            context: context,
            dependencies: dependencies[name]!,
          );
          final Object? output = await _runNodeWithRetry(
            context: context,
            node: node,
            nodeInput: nodeInput,
          );
          final Object? workflowOutput = _workflowOutputFromRaw(output);
          final Object? route = _routeFromOutput(output);
          return _NodeRunResult(
            name: name,
            output: workflowOutput,
            route: route,
            interruptIds: _interruptIdsFromOutput(output),
            waiting:
                (node.waitForOutput && workflowOutput == null && route == null),
          );
        }),
      );

      for (final _NodeRunResult result in results) {
        final NodeState state = context.nodeStates[result.name]!;
        pending.remove(result.name);
        if (result.output != null || result.route != null) {
          context.outputs[result.name] = result.output;
        }
        if (result.interruptIds.isNotEmpty || result.waiting) {
          state.status = NodeStatus.waiting;
          state.interrupts
            ..clear()
            ..addAll(result.interruptIds);
          continue;
        }
        context.outputs[result.name] = result.output;
        completed.add(result.name);
        if (state.resumeInputs.isNotEmpty) {
          state.resumeInputs.clear();
        }
        _activateDownstream(
          fromNode: result.name,
          route: result.route,
          active: active,
        );
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

  Future<Object?> _runNodeWithRetry({
    required WorkflowContext context,
    required BaseNode node,
    required Object? nodeInput,
  }) async {
    final RetryConfig? retry = node.retryConfig;
    final int maxAttempts = retry == null
        ? 1
        : (retry.maxAttempts < 1 ? 1 : retry.maxAttempts);
    final NodeState state = context.nodeStates.putIfAbsent(
      node.name,
      NodeState.new,
    );
    state.input = nodeInput;
    if (state.status == NodeStatus.inactive || state.runId == null) {
      state.runCounter += 1;
      state.runId = '${state.runCounter}';
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

  Event? _eventFromOutput(
    InvocationContext context,
    String author,
    Object? output,
  ) {
    if (output == null) {
      return null;
    }
    final NodeInfo nodeInfo = _nodeInfoForOutput(context, author);
    if (output is Event) {
      return output.nodeInfo.isEmpty
          ? output.copyWith(nodeInfo: nodeInfo)
          : output;
    }
    if (output is RequestInput) {
      return createRequestInputEvent(
        output,
        invocationId: context.invocationId,
        author: author,
      ).copyWith(nodeInfo: nodeInfo);
    }
    if (output is Content) {
      return Event(
        invocationId: context.invocationId,
        author: author,
        branch: context.branch,
        nodeInfo: nodeInfo.copyWith(messageAsOutput: true),
        content: output,
      );
    }
    final String text = output is String ? output : jsonEncode(output);
    return Event(
      invocationId: context.invocationId,
      author: author,
      branch: context.branch,
      nodeInfo: nodeInfo.copyWith(messageAsOutput: true),
      content: Content.modelText(text),
    );
  }
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

NodeInfo _nodeInfoForOutput(InvocationContext context, String nodeName) {
  final String workflowName = context.agent.name.isEmpty
      ? 'workflow'
      : context.agent.name;
  final String nodePath = '$workflowName@1/$nodeName@1';
  return NodeInfo(path: nodePath, outputFor: <String>[nodePath]);
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
