/// Experimental node-based workflow runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../agents/abort_signal.dart';
import '../agents/base_agent.dart';
import '../agents/context.dart';
import '../agents/invocation_context.dart';
import '../agents/llm/task/finish_task_tool.dart';
import '../agents/llm_agent.dart';
import '../agents/remote_a2a_agent.dart';
import '../errors/input_validation_error.dart';
import '../events/event.dart';
import '../events/event_actions.dart';
import '../events/node_path_builder.dart';
import '../events/request_input.dart';
import '../flows/llm_flows/functions.dart';
import '../models/llm_request.dart';
import '../sessions/in_memory_session_service.dart';
import '../sessions/session.dart';
import '../tools/agent_tool.dart';
import '../tools/base_tool.dart';
import '../tools/node_tool.dart';
import '../tools/tool_confirmation.dart';
import '../types/content.dart';
import 'workflow_tool.dart';
import 'edges_builder.dart';


part 'workflow_models_and_context.dart';
part 'workflow_nodes_and_edges.dart';
part 'workflow_execution_helpers.dart';
/// Sentinel node name used for workflow start edges.
// ignore: constant_identifier_names
const String START = 'START';

/// Default route value used by routed workflow edges.
// ignore: constant_identifier_names
const String DEFAULT_ROUTE = '__DEFAULT__';

/// Lower-camel alias for [DEFAULT_ROUTE].
const String defaultRoute = DEFAULT_ROUTE;

const String _workflowOutputOwner = r'$workflow';

/// Node-based workflow agent.
///
/// ```dart
/// final step1 = node((ctx, input) => 'Processed: $input', name: 'step_1');
/// final step2 = node((ctx, input) => '$input -> done', name: 'step_2');
///
/// final workflow = Workflow(
///   name: 'my_pipeline',
///   nodes: [step1, step2],
///   edges: [
///     Edge(fromNode: START, toNode: step1),
///     Edge(fromNode: step1, toNode: step2),
///   ],
/// );
/// ```
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
    _validateStaticGraphEdges(this.nodes, this.edges);
  }

  /// Creates a workflow using an [EdgesBuilder] graph definition callback.
  ///
  /// ```dart
  /// final workflow = Workflow.build(
  ///   name: 'support_triage',
  ///   nodes: [classify, category, billing, summarize],
  ///   buildEdges: (g) {
  ///     g.fromStart().chain([classify, category]).route((r) {
  ///       r.on('billing').then(billing);
  ///       r.otherwise(summarize);
  ///     });
  ///     g.from(billing).then(summarize);
  ///   },
  /// );
  /// ```
  factory Workflow.build({
    required String name,
    String description = '',
    required List<BaseNode> nodes,
    required void Function(EdgesBuilder g) buildEdges,
    int? maxConcurrency,
    Object? beforeAgentCallback,
    Object? afterAgentCallback,
  }) {
    return Workflow(
      name: name,
      description: description,
      nodes: nodes,
      edges: EdgesBuilder.buildEdges(buildEdges),
      maxConcurrency: maxConcurrency,
      beforeAgentCallback: beforeAgentCallback,
      afterAgentCallback: afterAgentCallback,
    );
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
      workflowRoot: _workflowRootPath(this),
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
    String? workflowPath,
  }) {
    final Map<String, BaseNode> byName = <String, BaseNode>{
      for (final BaseNode node in nodes) node.name: node,
    };
    return _workflowResultFromEvents(
      events,
      workflowName: name,
      staticNodes: byName,
      invocationId: invocationId,
      workflowPath: workflowPath,
    );
  }

  /// Wraps this workflow into an invokable [BaseTool].
  BaseTool asTool({
    String? name,
    String? description,
    Map<String, dynamic>? inputSchema,
    Map<String, dynamic>? outputSchema,
  }) {
    return WorkflowTool(
      workflow: this,
      name: name,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
    );
  }

  void _emitNodeCheckpoint(WorkflowContext context) {
    final InvocationContext? ic = context.invocationContext;
    if (ic == null || !ic.isResumable) {
      return;
    }
    final Map<String, Object?> nodes = <String, Object?>{
      for (final MapEntry<String, NodeState> entry
          in context.nodeStates.entries)
        entry.key: <String, Object?>{
          'status': entry.value.status.name,
          'interrupts': entry.value.interrupts,
          'resume_inputs': entry.value.resumeInputs,
        },
    };
    context._checkpointEvents.add(
      Event(
        invocationId: ic.invocationId,
        author: name,
        branch: ic.branch,
        actions: EventActions(agentState: <String, Object?>{'nodes': nodes}),
      ),
    );
  }

  void _emitEndOfAgent(WorkflowContext context) {
    final InvocationContext? ic = context.invocationContext;
    if (ic == null || !ic.isResumable) {
      return;
    }
    context._checkpointEvents.add(
      Event(
        invocationId: ic.invocationId,
        author: name,
        branch: ic.branch,
        actions: EventActions(endOfAgent: true),
      ),
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
      workflowRoot: _workflowRootPath(this, context),
    );
    workflowContext.onNodeStateChange = () =>
        _emitNodeCheckpoint(workflowContext);

    // Emit initial checkpoint of recovered node states when workflow starts
    _emitNodeCheckpoint(workflowContext);

    await _execute(workflowContext);

    final bool hasPendingInterrupts = workflowContext.nodeStates.values.any(
      (NodeState state) => _hasUnresolvedWaitingInterrupts(state),
    );
    if (!hasPendingInterrupts) {
      _emitEndOfAgent(workflowContext);
    }

    for (final Event event in workflowContext._checkpointEvents) {
      yield event;
    }

    final Map<String, BaseNode> byName = <String, BaseNode>{
      for (final BaseNode node in nodes) node.name: node,
    };
    final Set<String> outputKeys = <String>{
      ...workflowContext.outputs.keys,
      ...workflowContext._nodeEvents.keys,
      ...workflowContext._nodeOutputEvents.keys,
      for (final MapEntry<String, NodeState> entry
          in workflowContext.nodeStates.entries)
        if (_isWaitingForPredecessorTrigger(entry.value, byName[entry.key]))
          entry.key,
    };
    for (final String key in outputKeys) {
      if (key == START) {
        continue;
      }
      final Object? outputValue = workflowContext.outputs[key];
      final List<Event>? nodeEvents = workflowContext._nodeEvents[key];
      if (workflowContext.requestInputNodeKeys.contains(key)) {
        continue;
      }
      final bool isPrevCompleted = _isPreviouslyCompletedOutput(
        previousResult,
        key,
        historyEvents: context.session.events,
        workflowPath: _workflowRootPath(this, context),
      );
      if (nodeEvents != null) {
        for (final Event event in nodeEvents) {
          yield event;
        }
        continue;
      }
      if (isPrevCompleted) {
        continue;
      }
      final Object? eventOutput =
          workflowContext._nodeOutputEvents[key] ?? outputValue;
      final Event? event = _eventFromOutput(
        context,
        key,
        eventOutput,
        state: workflowContext.nodeStates[key],
      );
      if (event != null) {
        yield event;
      } else if (_isWaitingForPredecessorTrigger(
            workflowContext.nodeStates[key],
            byName[key],
          ) &&
          previousResult?.nodeStates[key]?.status != NodeStatus.waiting) {
        yield Event(
          invocationId: context.invocationId,
          author: key,
          branch: workflowContext.nodeStates[key]?.branch ?? context.branch,
          isolationScope: context.isolationScope,
          nodeInfo: _nodeInfoForOutput(
            context,
            key,
            outputForKeys: workflowContext.nodeStates[key]?.outputFor,
          ),
        );
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
    final Map<String, Set<String>> edgePredecessors = _edgePredecessors(byName);
    final Map<String, Set<String>> reachableFrom = _reachableFrom(byName);
    final Map<String, Set<String>> joinArrivals = <String, Set<String>>{};
    final Map<String, List<Object?>> triggerBuffer = <String, List<Object?>>{};
    _seedResumeInputs(context, byName);
    final Set<String> completed = <String>{
      START,
      for (final MapEntry<String, NodeState> entry
          in context.nodeStates.entries)
        if (_isCompletedNodeState(entry.value) && byName.containsKey(entry.key))
          entry.key,
    };
    context.outputs[START] = context.input;
    final Set<String> pending = <String>{};
    for (final String name in byName.keys) {
      if (completed.contains(name)) {
        continue;
      }
      final BaseNode node = byName[name]!;
      final NodeState? state = context.nodeStates[name];
      if (_hasUnresolvedWaitingInterrupts(
        state,
        rerunOnResume:
            node.rerunOnResume &&
            context.nodeStates.values.any(
              (NodeState s) => s.parentKey == name && s.interrupts.isNotEmpty,
            ),
      )) {
        continue;
      }
      if (_isWaitingForPredecessorTrigger(state, node)) {
        continue;
      }
      if (_usesTriggerBuffer(node, edgePredecessors)) {
        final bool isInactive =
            state == null || state.status == NodeStatus.inactive;
        if (isInactive && dependencies[name]!.contains(START)) {
          triggerBuffer.putIfAbsent(name, () => <Object?>[]).add(
            context.outputs[START],
          );
          pending.add(name);
        } else if (state?.status == NodeStatus.waiting &&
            (_rerunsWhileWaiting(node) || state!.resumeInputs.isNotEmpty)) {
          triggerBuffer.putIfAbsent(name, () => <Object?>[]).add(state?.input);
          pending.add(name);
        }
        continue;
      }
      pending.add(name);
    }
    final Set<String> active = edges.isEmpty
        ? byName.keys.toSet()
        : _initialActiveNodes(byName);
    for (final String completedNode in completed.toList()) {
      if (completedNode == START) {
        continue;
      }
      final Set<String> activatedTargets = _activateDownstream(
        context: context,
        fromNode: completedNode,
        route: context.nodeStates[completedNode]?.route,
        active: active,
        byName: byName,
        dependencies: dependencies,
        edgePredecessors: edgePredecessors,
        reachableFrom: reachableFrom,
        joinArrivals: joinArrivals,
        triggerBuffer: triggerBuffer,
        completed: completed,
        pending: pending,
        reactivateCompleted: false,
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
        edgePredecessors: edgePredecessors,
        reachableFrom: reachableFrom,
        joinArrivals: joinArrivals,
        triggerBuffer: triggerBuffer,
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
      // Serialize concurrency: while a task-mode agent node is waiting for
      // user input, do not schedule further parallel branches. The workflow
      // pauses until the task node is resumed. Mirrors upstream's
      // `_has_waiting_task_agent` guard in `_schedule_ready_nodes`.
      if (_hasWaitingTaskAgent(context)) {
        break;
      }

      final List<String> ready =
          pending
              .where(
                (String name) => _isNodeReady(
                  name: name,
                  byName: byName,
                  dependencies: dependencies,
                  edgePredecessors: edgePredecessors,
                  reachableFrom: reachableFrom,
                  joinArrivals: joinArrivals,
                  triggerBuffer: triggerBuffer,
                  active: active,
                  pending: pending,
                  completed: completed,
                  running: const <String, Future<_TaskOutcome>>{},
                ),
              )
              .toList()
            ..sort();
      if (ready.isEmpty) {
        throw StateError(
          'Workflow graph has unresolved or cyclic dependencies.',
        );
      }
      for (final String name in ready) {
        final Set<String>? arrivals = joinArrivals[name];
        if (arrivals != null) {
          final Set<String>? reachable = reachableFrom[name];
          if (reachable != null && reachable.contains(name)) {
            arrivals.removeAll(reachable);
          } else {
            joinArrivals.remove(name);
          }
        }
      }

      // Schedule all ready tasks, then drain them by completion order. When a
      // node fails, the workflow is cancelled immediately so still-running
      // siblings observe the cancellation. Sibling nodes that completed in the
      // same tick as the failure (i.e. already settled) still have their
      // outputs recorded before the workflow shuts down.
      final Map<String, Future<_TaskOutcome>> running =
          <String, Future<_TaskOutcome>>{
            for (final String name in ready)
              name:
                  _runReadyNode(
                    context: context,
                    byName: byName,
                    dependencies: dependencies,
                    triggerBuffer: triggerBuffer,
                    name: name,
                  ).then(
                    (_NodeRunResult result) => _TaskOutcome.success(result),
                    onError: (Object error, StackTrace stackTrace) =>
                        _TaskOutcome.failure(name, error, stackTrace),
                  ),
          };

      _TaskOutcome? firstFailure;
      while (running.isNotEmpty) {
        final _TaskOutcome outcome = await Future.any(running.values);
        running.remove(outcome.name);
        pending.remove(outcome.name);
        if (outcome.error != null) {
          // Cancel immediately on the first failure so still-running siblings
          // observe the cancellation, but keep draining already-settled
          // siblings so their outputs are recorded.
          if (firstFailure == null) {
            firstFailure = outcome;
            context._cancel(outcome.error!);
          }
          continue;
        }
        final _NodeRunResult result = outcome.result!;
        final bool completedNode = _recordNodeResult(context, result);
        if (!completedNode) {
          if (result.interruptIds.isEmpty &&
              (triggerBuffer[result.name]?.isNotEmpty ?? false)) {
            pending.add(result.name);
          }
          continue;
        }
        completed.add(result.name);
        final Set<String> activatedTargets = _activateDownstream(
          context: context,
          fromNode: result.name,
          route: result.route,
          active: active,
          byName: byName,
          dependencies: dependencies,
          edgePredecessors: edgePredecessors,
          reachableFrom: reachableFrom,
          joinArrivals: joinArrivals,
          triggerBuffer: triggerBuffer,
          completed: completed,
          pending: pending,
          reactivateCompleted: true,
        );
        if (activatedTargets.isEmpty) {
          _markTerminalOutputOwner(context, result.name);
        }
      }

      if (firstFailure != null) {
        Error.throwWithStackTrace(
          firstFailure.error!,
          firstFailure.stackTrace!,
        );
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
    required Map<String, Set<String>> edgePredecessors,
    required Map<String, Set<String>> reachableFrom,
    required Map<String, Set<String>> joinArrivals,
    required Map<String, List<Object?>> triggerBuffer,
    required Set<String> pending,
    required Set<String> completed,
    required Set<String> active,
    required int concurrencyLimit,
  }) async {
    final Map<String, Future<_TaskOutcome>> running =
        <String, Future<_TaskOutcome>>{};
    final Set<String> replayedInFlight = <String>{};
    while (pending.any(active.contains) || running.isNotEmpty) {
      // Serialize concurrency when a task-mode agent node is waiting: do not
      // schedule further parallel branches. If nothing is in flight, the
      // workflow pauses until the task node is resumed. Mirrors upstream's
      // `_has_waiting_task_agent` guard.
      if (_hasWaitingTaskAgent(context)) {
        if (running.isEmpty) {
          break;
        }
      }
      final int activeLiveCount = running.keys
          .where((String key) => !replayedInFlight.contains(key))
          .length;
      final int availableSlots = _hasWaitingTaskAgent(context)
          ? 0
          : concurrencyLimit - activeLiveCount;
      if (!_hasWaitingTaskAgent(context)) {
        final List<String> ready =
            pending
                .where(
                  (String name) => _isNodeReady(
                    name: name,
                    byName: byName,
                    dependencies: dependencies,
                    edgePredecessors: edgePredecessors,
                    reachableFrom: reachableFrom,
                    joinArrivals: joinArrivals,
                    triggerBuffer: triggerBuffer,
                    active: active,
                    pending: pending,
                    completed: completed,
                    running: running,
                  ),
                )
                .toList()
              ..sort();
        if (ready.isEmpty && running.isEmpty && pending.any(active.contains)) {
          throw StateError(
            'Workflow graph has unresolved or cyclic dependencies.',
          );
        }
        int remainingLiveSlots = availableSlots;
        for (final String name in ready) {
          final NodeState? nodeState = context.nodeStates[name];
          final bool isReplayed =
              nodeState != null && _isCompletedNodeState(nodeState);
          if (!isReplayed) {
            if (remainingLiveSlots <= 0) {
              continue;
            }
            remainingLiveSlots -= 1;
          } else {
            replayedInFlight.add(name);
          }
          pending.remove(name);
          final Set<String>? arrivals = joinArrivals[name];
          if (arrivals != null) {
            final Set<String>? reachable = reachableFrom[name];
            if (reachable != null && reachable.contains(name)) {
              arrivals.removeAll(reachable);
            } else {
              joinArrivals.remove(name);
            }
          }
          running[name] =
              _runReadyNode(
                context: context,
                byName: byName,
                dependencies: dependencies,
                triggerBuffer: triggerBuffer,
                name: name,
              ).then(
                (_NodeRunResult result) => _TaskOutcome.success(result),
                onError: (Object error, StackTrace stackTrace) =>
                    _TaskOutcome.failure(name, error, stackTrace),
              );
        }
      }
      if (running.isEmpty) {
        break;
      }

      final _TaskOutcome outcome = await Future.any(running.values);
      running.remove(outcome.name);
      replayedInFlight.remove(outcome.name);
      if (outcome.error != null) {
        // Drain remaining in-flight tasks so completed siblings still have
        // their outputs recorded, then propagate the first failure.
        final _TaskOutcome firstFailure = outcome;
        while (running.isNotEmpty) {
          final _TaskOutcome sibling = await Future.any(running.values);
          running.remove(sibling.name);
          if (sibling.error != null) {
            continue;
          }
          _recordNodeResult(context, sibling.result!);
        }
        context._cancel(firstFailure.error!);
        Error.throwWithStackTrace(
          firstFailure.error!,
          firstFailure.stackTrace!,
        );
      }
      final _NodeRunResult result = outcome.result!;
      final bool completedNode = _recordNodeResult(context, result);
      if (!completedNode) {
        if (result.interruptIds.isEmpty &&
            (triggerBuffer[result.name]?.isNotEmpty ?? false)) {
          pending.add(result.name);
        }
        continue;
      }
      completed.add(result.name);
      final Set<String> activatedTargets = _activateDownstream(
        context: context,
        fromNode: result.name,
        route: result.route,
        active: active,
        byName: byName,
        dependencies: dependencies,
        edgePredecessors: edgePredecessors,
        reachableFrom: reachableFrom,
        joinArrivals: joinArrivals,
        triggerBuffer: triggerBuffer,
        completed: completed,
        pending: pending,
        reactivateCompleted: true,
      );
      if (activatedTargets.isEmpty) {
        _markTerminalOutputOwner(context, result.name);
      }
    }
  }

  Map<String, Set<String>> _edgePredecessors(Map<String, BaseNode> byName) {
    final Map<String, Set<String>> preds = <String, Set<String>>{
      for (final String name in byName.keys) name: <String>{},
    };
    for (final Edge edge in edges) {
      if (edge.fromNode != START && preds.containsKey(edge.toNode)) {
        preds[edge.toNode]!.add(edge.fromNode);
      }
    }
    return preds;
  }

  Map<String, Set<String>> _reachableFrom(Map<String, BaseNode> byName) {
    final Map<String, Set<String>> adj = <String, Set<String>>{
      for (final String name in byName.keys) name: <String>{},
    };
    for (final BaseNode node in byName.values) {
      for (final String dep in node.dependsOn) {
        if (adj.containsKey(dep)) {
          adj[dep]!.add(node.name);
        }
      }
    }
    for (final Edge edge in edges) {
      if (edge.fromNode != START && adj.containsKey(edge.fromNode)) {
        adj[edge.fromNode]!.add(edge.toNode);
      }
    }
    final Map<String, Set<String>> reachable = <String, Set<String>>{};
    for (final String start in byName.keys) {
      final Set<String> visited = <String>{};
      final List<String> queue = <String>[...adj[start]!];
      while (queue.isNotEmpty) {
        final String current = queue.removeLast();
        if (visited.add(current)) {
          queue.addAll(adj[current] ?? const <String>{});
        }
      }
      reachable[start] = visited;
    }
    return reachable;
  }

  bool _isNodeReady({
    required String name,
    required Map<String, BaseNode> byName,
    required Map<String, Set<String>> dependencies,
    required Map<String, Set<String>> edgePredecessors,
    required Map<String, Set<String>> reachableFrom,
    required Map<String, Set<String>> joinArrivals,
    required Map<String, List<Object?>> triggerBuffer,
    required Set<String> active,
    required Set<String> pending,
    required Set<String> completed,
    required Map<String, Future<_TaskOutcome>> running,
  }) {
    if (!active.contains(name)) {
      return false;
    }
    final BaseNode node = byName[name]!;
    if (_usesTriggerBuffer(node, edgePredecessors)) {
      return !running.containsKey(name) &&
          (triggerBuffer[name]?.isNotEmpty ?? false);
    }
    if (node.requiresAllPredecessors) {
      final Set<String> arrivals = joinArrivals[name] ?? const <String>{};
      final Set<String> edgePreds = edgePredecessors[name] ?? const <String>{};
      for (final String p in dependencies[name]!) {
        if (p == START) {
          continue;
        }
        if (!completed.contains(p)) {
          return false;
        }
        if (edgePreds.contains(p) && !arrivals.contains(p)) {
          return false;
        }
        if (running.containsKey(p) ||
            (pending.contains(p) && active.contains(p))) {
          return false;
        }
      }
      return true;
    }

    for (final String dep in node.dependsOn) {
      if (!completed.contains(dep)) {
        return false;
      }
    }
    final Set<String> reachable = reachableFrom[name] ?? const <String>{};
    for (final String pred in edgePredecessors[name] ?? const <String>{}) {
      if (reachable.contains(pred)) {
        // Loop back-edge: do not block initial execution on a downstream loop body node.
        continue;
      }
      final bool predHasUnconditionalEdge = edges.any(
        (Edge e) => e.fromNode == pred && e.toNode == name && e.route == null,
      );
      if (!predHasUnconditionalEdge) {
        continue;
      }
      final bool predInFlight =
          running.containsKey(pred) ||
          (pending.contains(pred) && active.contains(pred));
      if (predInFlight || !completed.contains(pred)) {
        return false;
      }
    }
    return true;
  }

  // Whether any task-mode agent node in this graph is currently waiting.
  //
  // Task-mode agents are multi-turn and pause for user input. While one is
  // waiting, the scheduler stops dispatching further parallel branches so the
  // suspended task keeps exclusive control of the conversation.
  bool _hasWaitingTaskAgent(WorkflowContext context) {
    for (final BaseNode node in nodes) {
      if (node is AgentNode &&
          node.agent is LlmAgent &&
          (node.agent as LlmAgent).mode == 'task') {
        final NodeState? state = context.nodeStates[node.name];
        if (state != null && state.status == NodeStatus.waiting) {
          return true;
        }
      }
    }
    return false;
  }

  Future<_NodeRunResult> _runReadyNode({
    required WorkflowContext context,
    required Map<String, BaseNode> byName,
    required Map<String, Set<String>> dependencies,
    required Map<String, List<Object?>> triggerBuffer,
    required String name,
  }) async {
    final BaseNode node = byName[name]!;
    if (node is RequestInput) {
      context.requestInputNodeKeys.add(name);
    }
    final List<Object?>? queuedTriggers = triggerBuffer[name];
    final Object? nodeInput =
        (queuedTriggers != null && queuedTriggers.isNotEmpty)
        ? queuedTriggers.removeAt(0)
        : _nodeInput(
            context: context,
            dependencies: dependencies[name]!,
            node: node,
          );
    final NodeState? state = context.nodeStates[name];
    final WorkflowContext nodeContext = context._childExecutionContext(
      resumeInputs: state?.resumeInputs.isNotEmpty == true
          ? Map<String, Object?>.from(state!.resumeInputs)
          : const <String, Object?>{},
    );
    try {
      final Object? output = await _runNodeWithRetry(
        context: nodeContext,
        node: node,
        nodeInput: nodeInput,
      );
      return _resultFromRawNodeOutput(node, output, context: nodeContext);
    } on NodeInterruptedError catch (error) {
      return _NodeRunResult(
        name: name,
        output: null,
        interruptIds: <String>{
          ...nodeContext.interruptIds,
          ...error.interruptIds,
        },
        waiting: true,
      );
    }
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
      if (!_seedNodeResumeInputs(
        state,
        context.resumeInputs,
        rerunOnResume: node.rerunOnResume,
      )) {
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
        dependencies[edge.toNode]!.add(START);
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
    required WorkflowContext context,
    required String fromNode,
    required Object? route,
    required Set<String> active,
    required Map<String, BaseNode> byName,
    required Map<String, Set<String>> dependencies,
    required Map<String, Set<String>> edgePredecessors,
    required Map<String, Set<String>> reachableFrom,
    required Map<String, Set<String>> joinArrivals,
    required Map<String, List<Object?>> triggerBuffer,
    required Set<String> completed,
    required Set<String> pending,
    required bool reactivateCompleted,
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
    for (final String target in activatedTargets) {
      final BaseNode? targetNode = byName[target];
      if (targetNode == null) {
        continue;
      }
      if (_usesTriggerBuffer(targetNode, edgePredecessors)) {
        final NodeState? targetState = context.nodeStates[target];
        final bool isTargetInactive =
            targetState == null || targetState.status == NodeStatus.inactive;
        if (reactivateCompleted || isTargetInactive) {
          triggerBuffer.putIfAbsent(target, () => <Object?>[]).add(
            context.outputs[fromNode],
          );
          completed.remove(target);
          pending.add(target);
        }
        continue;
      }
      if (targetNode.requiresAllPredecessors) {
        joinArrivals.putIfAbsent(target, () => <String>{}).add(fromNode);
      }
      if (reactivateCompleted && completed.contains(target)) {
        if (!targetNode.requiresAllPredecessors) {
          completed.remove(target);
          pending.add(target);
          for (final MapEntry<String, Set<String>> entry
              in joinArrivals.entries) {
            final Set<String>? reachable = reachableFrom[entry.key];
            if (reachable == null ||
                !reachable.contains(entry.key) ||
                reachable.contains(target)) {
              entry.value.remove(target);
            }
          }
        } else {
          final Set<String> arrivals = joinArrivals[target] ?? const <String>{};
          final Set<String> edgePreds =
              edgePredecessors[target] ?? const <String>{};
          final bool allArrived = dependencies[target]!.every(
            (String p) =>
                p == START ||
                (completed.contains(p) &&
                    (!edgePreds.contains(p) || arrivals.contains(p))),
          );
          if (allArrived) {
            completed.remove(target);
            pending.add(target);
          }
        }
      }
    }
    return activatedTargets;
  }

  Object? _nodeInput({
    required WorkflowContext context,
    required Set<String> dependencies,
    BaseNode? node,
  }) {
    if (dependencies.isEmpty) {
      return context.input;
    }
    if (dependencies.length == 1 && node is! JoinNode) {
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
    final NodeInfo nodeInfo = _nodeInfoForOutput(
      context,
      author,
      outputForKeys: state?.outputFor,
    );
    final String? publishBranch =
        (output is Event && output.getFunctionResponses().isNotEmpty)
        ? (state?.branch ?? context.branch)
        : (state?.outputBranch ?? state?.branch ?? context.branch);
    if (output == null) {
      if (state?.route != null) {
        return Event(
          invocationId: context.invocationId,
          author: author,
          branch: publishBranch,
          isolationScope: context.isolationScope,
          nodeInfo: nodeInfo,
          actions: EventActions(route: state!.route),
        );
      }
      return null;
    }
    if (output is Event) {
      Event event = output.nodeInfo.isEmpty
          ? output.copyWith(nodeInfo: nodeInfo)
          : output;
      if (event.invocationId.isEmpty) {
        event = event.copyWith(invocationId: context.invocationId);
      }
      if (event.author.isEmpty) {
        event = event.copyWith(author: author);
      }
      if (event.branch == null) {
        event = event.copyWith(branch: publishBranch);
      }
      if (event.isolationScope == null) {
        event = event.copyWith(isolationScope: context.isolationScope);
      }
      if (state?.route != null && event.actions.route == null) {
        event = event.copyWith(
          actions: event.actions.copyWith(route: state!.route),
        );
      }
      return event;
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
        branch: publishBranch,
        isolationScope: event.isolationScope ?? context.isolationScope,
      );
    }
    if (output is Content) {
      return Event(
        invocationId: context.invocationId,
        author: author,
        branch: publishBranch,
        isolationScope: context.isolationScope,
        nodeInfo: nodeInfo.copyWith(messageAsOutput: true),
        content: output,
        actions: state?.route == null ? null : EventActions(route: state!.route),
      );
    }
    if (output is Uint8List) {
      return Event(
        invocationId: context.invocationId,
        author: author,
        branch: publishBranch,
        isolationScope: context.isolationScope,
        nodeInfo: nodeInfo,
        output: output,
        actions: state?.route == null ? null : EventActions(route: state!.route),
      );
    }
    final String text = output is String ? output : jsonEncode(output);
    return Event(
      invocationId: context.invocationId,
      author: author,
      branch: publishBranch,
      isolationScope: context.isolationScope,
      nodeInfo: nodeInfo.copyWith(messageAsOutput: true),
      content: Content.modelText(text),
      actions: state?.route == null ? null : EventActions(route: state!.route),
    );
  }
}

WorkflowResult? _rehydratedResultForContext(
  Workflow workflow,
  InvocationContext context,
) {
  final bool hasUserFunctionResponse = context.session.events.any(
    (Event event) =>
        event.invocationId == context.invocationId &&
        event.author == 'user' &&
        event.getFunctionResponses().isNotEmpty,
  );
  if (!context.isResumable && !hasUserFunctionResponse) {
    return null;
  }
  final String rootPath = _workflowRootPath(workflow, context);
  final bool hasWorkflowEvents = context.session.events.any((Event event) {
    return event.invocationId == context.invocationId &&
        _isWorkflowNodePath(event.nodeInfo.path, rootPath);
  });
  if (!hasWorkflowEvents) {
    return null;
  }
  return workflow.rehydrateResultFromEvents(
    context.session.events,
    invocationId: context.invocationId,
    workflowPath: rootPath,
  );
}

