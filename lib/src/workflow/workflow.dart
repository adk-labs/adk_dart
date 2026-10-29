/// Experimental node-based workflow runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

/// Sentinel node name used for workflow start edges.
// ignore: constant_identifier_names
const String START = 'START';

/// Default route value used by routed workflow edges.
// ignore: constant_identifier_names
const String DEFAULT_ROUTE = '__DEFAULT__';

/// Lower-camel alias for [DEFAULT_ROUTE].
const String defaultRoute = DEFAULT_ROUTE;

const String _workflowOutputOwner = r'$workflow';

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

  /// Intermediate checkpoint events.
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
            throw NodeInterruptedError();
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
    if (result.interruptIds.isNotEmpty) {
      interruptIds.addAll(result.interruptIds);
    }
    if (raiseOnWait && (result.waiting || result.interruptIds.isNotEmpty)) {
      throw NodeInterruptedError();
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
  RetryConfig? retryConfig;

  /// Optional per-attempt timeout.
  final Duration? timeout;

  /// Whether this node requires all predecessor nodes to complete before running.
  bool get requiresAllPredecessors => false;

  /// Validates outgoing [edges] originating from this node during graph validation.
  void validateOutgoingEdges(List<Edge> edges) {}

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
  ///
  /// When [requireConfirmation] is configured (not `null` and not `false`),
  /// [rerunOnResume] defaults to `true` and cannot be `false`.
  FunctionNode({
    required this.function,
    required super.name,
    super.description,
    super.dependsOn,
    bool? rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
    this.requireConfirmation = false,
  }) : super(
         rerunOnResume:
             rerunOnResume ?? _hasConfirmationFlag(requireConfirmation),
       ) {
    if (requireConfirmation != null &&
        requireConfirmation is! bool &&
        requireConfirmation is! Function) {
      throw WorkflowConfigurationError(
        'requireConfirmation must be a bool or Function.',
      );
    }
    if (_hasConfirmationFlag(requireConfirmation) && rerunOnResume == false) {
      throw WorkflowConfigurationError(
        'FunctionNode with require_confirmation requires '
        'rerun_on_resume=True. The node must rerun after confirmation is '
        'provided.',
      );
    }
  }

  /// Function invoked for this node.
  final WorkflowFunction function;

  /// Whether this node requires user confirmation (`bool` or predicate `Function`).
  final Object? requireConfirmation;

  @override
  FutureOr<Object?> run(WorkflowContext context, Object? nodeInput) {
    return _executeFunctionNode(this, context, nodeInput);
  }
}

bool _hasConfirmationFlag(Object? requireConfirmation) {
  return requireConfirmation != null && requireConfirmation != false;
}

FutureOr<Object?> _executeFunctionNode(
  FunctionNode node,
  WorkflowContext context,
  Object? nodeInput,
) async {
  bool resumedConfirmation = false;
  if (_hasConfirmationFlag(node.requireConfirmation)) {
    final String interruptId = confirmationInterruptId(context.nodePath);
    final Object? confResponse = context.resumeInputs[interruptId];
    if (confResponse != null) {
      resumedConfirmation = true;
      context.toolConfirmation = _parseWorkflowToolConfirmation(confResponse);
    }
    if (context.toolConfirmation != null) {
      if (context.toolConfirmation!.confirmed != true) {
        return Event(
          invocationId: context.invocationContext?.invocationId ?? '',
          author: node.name,
          output: <String, Object?>{'error': 'This tool call is rejected.'},
        );
      }
    } else {
      final bool needsConfirmation = await _evaluateRequireConfirmation(
        node.requireConfirmation,
        context,
        nodeInput,
      );
      if (needsConfirmation) {
        final Map<String, Object?> payloadArgs = _confirmationArgsFromInput(
          nodeInput,
        );
        return RequestInput(
          interruptId: interruptId,
          message: 'Please approve or reject the tool call ${node.name}().',
          payload: <String, Object?>{
            'tool_name': node.name,
            'args': payloadArgs,
          },
          responseSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'hint': <String, Object?>{'type': 'string'},
              'confirmed': <String, Object?>{'type': 'boolean'},
              'payload': <String, Object?>{},
            },
          },
        );
      }
    }
  }

  final Object? result = await node.function(context, nodeInput);
  if (result == null &&
      (resumedConfirmation ||
          (context.resumeInputs.isNotEmpty &&
              context.invocationContext != null &&
              !node.waitForOutput)) &&
      !context._hasDirectOutput &&
      context.route == null) {
    return Event(
      invocationId: context.invocationContext?.invocationId ?? '',
      author: node.name,
    );
  }
  return result;
}

ToolConfirmation _parseWorkflowToolConfirmation(Object? response) {
  if (response is ToolConfirmation) {
    return response;
  }
  if (response is bool) {
    return ToolConfirmation(confirmed: response);
  }
  if (response is Map) {
    final Object? confirmedValue = response['confirmed'];
    if (confirmedValue != null && confirmedValue is! bool) {
      throw WorkflowDataError(
        'Invalid tool confirmation response: $response',
      );
    }
    final Object? hintValue = response['hint'];
    if (hintValue != null && hintValue is! String) {
      throw WorkflowDataError(
        'Invalid tool confirmation response: $response',
      );
    }
    return ToolConfirmation(
      confirmed: confirmedValue as bool? ?? false,
      hint: hintValue as String?,
      payload: response['payload'],
    );
  }
  throw WorkflowDataError(
    'A tool confirmation response must be a ToolConfirmation payload, '
    'but got ${response.runtimeType}.',
  );
}

Future<bool> _evaluateRequireConfirmation(
  Object? requireConfirmation,
  WorkflowContext context,
  Object? nodeInput,
) async {
  if (requireConfirmation is bool) {
    return requireConfirmation;
  }
  if (requireConfirmation is Function) {
    Object? rawResult;
    if (requireConfirmation is FutureOr<Object?> Function(
      WorkflowContext,
      Object?,
    )) {
      rawResult = await requireConfirmation(context, nodeInput);
    } else if (requireConfirmation is FutureOr<Object?> Function(
      WorkflowContext,
    )) {
      rawResult = await requireConfirmation(context);
    } else if (requireConfirmation is FutureOr<Object?> Function()) {
      rawResult = await requireConfirmation();
    } else {
      try {
        rawResult = await Function.apply(
          requireConfirmation,
          <Object?>[context, nodeInput],
        );
      } on NoSuchMethodError {
        try {
          rawResult = await Function.apply(
            requireConfirmation,
            <Object?>[nodeInput],
          );
        } on NoSuchMethodError {
          rawResult = await Function.apply(requireConfirmation, const <Object?>[]);
        }
      }
    }
    if (rawResult is bool) {
      return rawResult;
    }
    if (rawResult is String) {
      return rawResult.isNotEmpty;
    }
    if (rawResult is num) {
      return rawResult != 0;
    }
    if (rawResult is Iterable) {
      return rawResult.isNotEmpty;
    }
    if (rawResult is Map) {
      return rawResult.isNotEmpty;
    }
    return rawResult != null;
  }
  return false;
}

Map<String, Object?> _confirmationArgsFromInput(Object? nodeInput) {
  if (nodeInput == null || nodeInput is Content) {
    return <String, Object?>{};
  }
  if (nodeInput is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in nodeInput.entries)
        '${entry.key}': _jsonSafeConfirmationValue(entry.value),
    };
  }
  return <String, Object?>{
    'node_input': _jsonSafeConfirmationValue(nodeInput),
  };
}

Object? _jsonSafeConfirmationValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_jsonSafeConfirmationValue).toList(growable: false);
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _jsonSafeConfirmationValue(entry.value),
    };
  }
  try {
    return (value as dynamic).toJson();
  } catch (_) {
    return '$value';
  }
}

/// Convenience wrapper matching Python's `node(...)` helper.
FunctionNode node(
  WorkflowFunction function, {
  required String name,
  String description = '',
  List<String>? dependsOn,
  bool? rerunOnResume,
  RetryConfig? retryConfig,
  Duration? timeout,
  Object? requireConfirmation,
}) {
  return buildNode(
        function,
        name: name,
        description: description,
        dependsOn: dependsOn,
        rerunOnResume: rerunOnResume,
        retryConfig: retryConfig,
        timeout: timeout,
        requireConfirmation: requireConfirmation,
      )
      as FunctionNode;
}

/// Converts a workflow-compatible object into a [BaseNode].
///
/// Supports existing [BaseNode] instances, [BaseTool] values, [BaseAgent]
/// values, and [WorkflowFunction] callbacks.
///
/// Throws an [UnsupportedError] when overriding an existing node is requested,
/// a [WorkflowConfigurationError] for invalid `requireConfirmation` settings,
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
  Object? requireConfirmation,
}) {
  if (nodeLike is NodeTool) {
    return buildNode(
      nodeLike.node,
      name: name,
      description: description,
      dependsOn: dependsOn,
      rerunOnResume: rerunOnResume,
      waitForOutput: waitForOutput,
      retryConfig: retryConfig,
      timeout: timeout,
      requireConfirmation: requireConfirmation,
    );
  }
  if (nodeLike is BaseNode) {
    if (nodeLike is FunctionNode) {
      final Object? effectiveConfirmation =
          requireConfirmation ?? nodeLike.requireConfirmation;
      if (_hasConfirmationFlag(effectiveConfirmation) &&
          rerunOnResume == false) {
        throw WorkflowConfigurationError(
          'FunctionNode with require_confirmation requires '
          'rerun_on_resume=True. The node must rerun after confirmation is '
          'provided.',
        );
      }
    } else if (_hasConfirmationFlag(requireConfirmation)) {
      throw WorkflowConfigurationError(
        'require_confirmation is only supported on FunctionNode, got '
        '${nodeLike.runtimeType}.',
      );
    }
    if (name == null &&
        description.isEmpty &&
        dependsOn == null &&
        rerunOnResume == null &&
        waitForOutput == null &&
        retryConfig == null &&
        timeout == null &&
        (requireConfirmation == null ||
            (nodeLike is! FunctionNode && requireConfirmation == false))) {
      return nodeLike;
    }
    throw UnsupportedError(
      'Cannot override fields for existing node `${nodeLike.name}`.',
    );
  }
  if (nodeLike is BaseTool) {
    if (_hasConfirmationFlag(requireConfirmation)) {
      throw WorkflowConfigurationError(
        'require_confirmation is only supported on FunctionNode, got '
        '${nodeLike.runtimeType}.',
      );
    }
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
    if (_hasConfirmationFlag(requireConfirmation)) {
      throw WorkflowConfigurationError(
        'require_confirmation is only supported on FunctionNode, got '
        '${nodeLike.runtimeType}.',
      );
    }
    final bool agentWaitForOutput =
        waitForOutput ??
        ((nodeLike is LlmAgent && nodeLike.mode == 'task') ||
            (nodeLike is RemoteA2aAgent && nodeLike.mode == 'task'));
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
      rerunOnResume: rerunOnResume,
      waitForOutput: waitForOutput ?? false,
      retryConfig: retryConfig,
      timeout: timeout,
      requireConfirmation: requireConfirmation ?? false,
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
  bool get requiresAllPredecessors => true;

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
    BaseNode wrappedNode = _buildParallelWorkerNode(node);
    if (retryConfig != null) {
      wrappedNode = _withRetryConfig(wrappedNode, retryConfig);
    }
    final int? resolvedLimit = maxParallelWorkers ?? maxConcurrency;
    if (resolvedLimit != null && resolvedLimit < 1) {
      throw ArgumentError(
        'maxParallelWorkers must be greater than or equal to 1.',
      );
    }
    return ParallelWorker._(
      wrappedNode: wrappedNode,
      maxParallelWorkers: resolvedLimit,
      timeout: timeout,
    );
  }

  ParallelWorker._({
    required this.wrappedNode,
    required this.maxParallelWorkers,
    super.timeout,
  }) : super(name: wrappedNode.name, rerunOnResume: true);

  /// Wrapped child node.
  final BaseNode wrappedNode;

  /// Maximum worker tasks to run at once. `null` means unlimited.
  final int? maxParallelWorkers;

  /// Deprecated. Use [maxParallelWorkers] instead.
  @Deprecated('Use maxParallelWorkers instead.')
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
    var stopScheduling = false;
    Object? firstError;
    StackTrace? firstStackTrace;
    NodeInterruptedError? interruptedError;
    StackTrace? interruptedStackTrace;

    Future<void> worker() async {
      while (true) {
        if (cancelRemaining || stopScheduling) {
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
          if (context.interruptIds.isNotEmpty) {
            stopScheduling = true;
          }
        } on NodeInterruptedError catch (error, stackTrace) {
          stopScheduling = true;
          interruptedError ??= error;
          interruptedStackTrace ??= stackTrace;
          return;
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
    if (interruptedError != null) {
      Error.throwWithStackTrace(interruptedError!, interruptedStackTrace!);
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

/// Returns the effective [RetryConfig] configured on [node], unwrapping [ParallelWorker] if needed.
RetryConfig? nodeRetryConfig(BaseNode node) {
  if (node.retryConfig != null) {
    return node.retryConfig;
  }
  if (node is ParallelWorker) {
    return nodeRetryConfig(node.wrappedNode);
  }
  return null;
}

/// Whether [node] has an explicit [RetryConfig] configured directly or on its wrapped worker.
bool hasOwnRetryConfig(BaseNode node) => nodeRetryConfig(node) != null;

/// Returns a copy of [node] with [retryConfig] applied.
BaseNode withRetryConfig(BaseNode node, RetryConfig? retryConfig) =>
    _withRetryConfig(node, retryConfig);

BaseNode _withRetryConfig(BaseNode node, RetryConfig? retryConfig) {
  if (node is FunctionNode) {
    return FunctionNode(
      function: node.function,
      name: node.name,
      description: node.description,
      dependsOn: node.dependsOn,
      rerunOnResume: node.rerunOnResume,
      waitForOutput: node.waitForOutput,
      retryConfig: retryConfig,
      timeout: node.timeout,
      requireConfirmation: node.requireConfirmation,
    );
  }
  if (node is ToolNode) {
    return ToolNode(
      tool: node.tool,
      name: node.name,
      description: node.description,
      dependsOn: node.dependsOn,
      rerunOnResume: node.rerunOnResume,
      waitForOutput: node.waitForOutput,
      retryConfig: retryConfig,
      timeout: node.timeout,
    );
  }
  if (node is AgentNode) {
    final BaseAgent? previousParent = node.agent.parentAgent;
    final AgentNode cloned = AgentNode(
      agent: node.agent,
      name: node.name,
      description: node.description,
      dependsOn: node.dependsOn,
      rerunOnResume: node.rerunOnResume,
      waitForOutput: node.waitForOutput,
      retryConfig: retryConfig,
      timeout: node.timeout,
    );
    node.agent.parentAgent = previousParent;
    return cloned;
  }
  if (node is ParallelWorker) {
    return ParallelWorker._(
      wrappedNode: _withRetryConfig(node.wrappedNode, retryConfig),
      maxParallelWorkers: node.maxParallelWorkers,
      timeout: node.timeout,
    );
  }
  node.retryConfig = retryConfig;
  return node;
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

    final FunctionDeclaration? decl = tool.getDeclaration();
    if (decl != null) {
      final Object? req = decl.parameters['required'];
      if (req is List) {
        final Map<String, Object?> sessionState =
            invocationContext.session.state;
        for (final Object? p in req) {
          if (p is String &&
              !args.containsKey(p) &&
              sessionState.containsKey(p)) {
            args[p] = sessionState[p];
          }
        }
      }
    }

    final Object? result = await tool.run(args: args, toolContext: toolContext);
    if (toolContext.actions.stateDelta.isNotEmpty) {
      invocationContext.session.state.addAll(toolContext.actions.stateDelta);
    }
    return result;
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
      llmAgent.mode ??= 'single_turn';
      // Only default includeContents to 'none' when the user has not
      // explicitly set it (i.e. it is still at the constructor default
      // value of 'default').
      if (llmAgent.mode == 'single_turn' &&
          llmAgent.includeContents == 'default') {
        llmAgent.includeContents = 'none';
      }
    }

    // Enforce the node input boundary against the agent's input schema before
    // wrapping the payload into Content. Matches upstream's strict validation
    // for LlmAgent workflow nodes.
    Object? validatedInput = nodeInput;
    if (agent is LlmAgent) {
      validatedInput = validateNodeData(
        (agent as LlmAgent).inputSchema,
        nodeInput,
      );
    }

    final InvocationContext parentContext =
        context.invocationContext ?? _standaloneInvocationContext(name);
    final bool isResuming = context.resumeInputs.isNotEmpty;
    final Content? userContent = (validatedInput == null || isResuming)
        ? null
        : _contentFromNodeInput(validatedInput);
    final String? nodeKey = context._currentNodeKey;
    final bool collectNestedWorkflowEvents =
        agent is Workflow &&
        nodeKey != null &&
        context.invocationContext != null;
    final String? ownerPath = collectNestedWorkflowEvents
        ? _nodePathForOutputKey(parentContext, nodeKey)
        : null;
    final String? nodeBranch =
        ownerPath ??
        (nodeKey != null ? context.nodeStates[nodeKey]?.branch : null) ??
        parentContext.branch;
    final InvocationContext agentContext = parentContext.copyWith(
      agent: agent,
      userContent: userContent,
      branch: nodeBranch,
    );
    final List<Event> nestedEvents = <Event>[];
    final bool isTaskMode =
        (agent is LlmAgent && (agent as LlmAgent).mode == 'task') ||
        (agent is RemoteA2aAgent && (agent as RemoteA2aAgent).mode == 'task');
    final Set<String> taskSubagentToolNames = <String>{
      if (agent is LlmAgent && (agent as LlmAgent).mode == 'task')
        for (final Object tool in (agent as LlmAgent).tools)
          if (tool is TaskAgentTool) tool.name,
    };
    Map<String, dynamic>? pendingFinishArgs;
    String? pendingFinishCallId;

    Event? finalEvent;
    await for (final Event event in agent.runAsync(agentContext)) {
      _mergeStateDelta(agentContext.session, event.actions.stateDelta);
      if (isTaskMode) {
        final List<FunctionCall> calls = event.getFunctionCalls();
        final bool hasTaskSubagentCall = calls.any(
          (FunctionCall call) => taskSubagentToolNames.contains(call.name),
        );
        for (final FunctionCall call in calls) {
          if (call.name == finishTaskToolName && !hasTaskSubagentCall) {
            pendingFinishArgs = Map<String, dynamic>.from(call.args);
            pendingFinishCallId = call.id;
          }
        }
        for (final FunctionResponse response in event.getFunctionResponses()) {
          if (response.name == finishTaskToolName &&
              (pendingFinishCallId == null ||
                  response.id == pendingFinishCallId)) {
            if (response.response['result'] == finishTaskErrorResult ||
                (event.errorMessage != null &&
                    event.errorMessage!.isNotEmpty)) {
              return <String, Object?>{
                'error': event.errorMessage ?? finishTaskErrorResult,
              };
            }
            if (response.response['result'] == finishTaskSuccessResult &&
                pendingFinishArgs != null) {
              final Object? outputSchema = agent is LlmAgent
                  ? (agent as LlmAgent).outputSchema
                  : agent is RemoteA2aAgent
                  ? (agent as RemoteA2aAgent).outputSchema
                  : null;
              final Object? taskOutput = _extractTaskOutput(
                outputSchema,
                pendingFinishArgs,
              );
              if (agent is LlmAgent) {
                final LlmAgent llmAgent = agent as LlmAgent;
                if (llmAgent.outputKey != null && taskOutput != null) {
                  agentContext.session.state[llmAgent.outputKey!] = taskOutput;
                }
              }
              return taskOutput;
            }
          }
        }
      }
      if (event.isFinalResponse() &&
          event.actions.endOfAgent == null &&
          event.actions.agentState == null) {
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
    final Object? finalOutput = _outputFromAgentEvent(finalEvent);
    if (agent is LlmAgent) {
      final LlmAgent llmAgent = agent as LlmAgent;
      if (llmAgent.outputKey != null && finalOutput != null) {
        agentContext.session.state[llmAgent.outputKey!] = finalOutput;
      }
    }
    return finalOutput;
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

    final Set<String> outputKeys = <String>{
      ...workflowContext.outputs.keys,
      ...workflowContext._nodeEvents.keys,
      ...workflowContext._nodeOutputEvents.keys,
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
    _seedResumeInputs(context, byName);
    final Set<String> completed = <String>{
      START,
      for (final MapEntry<String, NodeState> entry
          in context.nodeStates.entries)
        if (_isCompletedNodeState(entry.value) && byName.containsKey(entry.key))
          entry.key,
    };
    context.outputs[START] = context.input;
    final Set<String> pending = <String>{
      for (final String name in byName.keys)
        if (!completed.contains(name) &&
            !_hasUnresolvedWaitingInterrupts(
              context.nodeStates[name],
              rerunOnResume:
                  (byName[name]?.rerunOnResume ?? false) &&
                  context.nodeStates.values.any(
                    (NodeState s) =>
                        s.parentKey == name && s.interrupts.isNotEmpty,
                  ),
            ))
          name,
    };
    final Set<String> active = edges.isEmpty
        ? byName.keys.toSet()
        : _initialActiveNodes(byName);
    for (final String completedNode in completed.toList()) {
      if (completedNode == START) {
        continue;
      }
      final Set<String> activatedTargets = _activateDownstream(
        fromNode: completedNode,
        route: context.nodeStates[completedNode]?.route,
        active: active,
        byName: byName,
        dependencies: dependencies,
        edgePredecessors: edgePredecessors,
        joinArrivals: joinArrivals,
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
        joinArrivals.remove(name);
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
          continue;
        }
        completed.add(result.name);
        final Set<String> activatedTargets = _activateDownstream(
          fromNode: result.name,
          route: result.route,
          active: active,
          byName: byName,
          dependencies: dependencies,
          edgePredecessors: edgePredecessors,
          joinArrivals: joinArrivals,
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
          joinArrivals.remove(name);
          running[name] =
              _runReadyNode(
                context: context,
                byName: byName,
                dependencies: dependencies,
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
        continue;
      }
      completed.add(result.name);
      final Set<String> activatedTargets = _activateDownstream(
        fromNode: result.name,
        route: result.route,
        active: active,
        byName: byName,
        dependencies: dependencies,
        edgePredecessors: edgePredecessors,
        joinArrivals: joinArrivals,
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
    required Set<String> active,
    required Set<String> pending,
    required Set<String> completed,
    required Map<String, Future<_TaskOutcome>> running,
  }) {
    if (!active.contains(name)) {
      return false;
    }
    final BaseNode node = byName[name]!;
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

  /// Whether any task-mode agent node in this graph is currently waiting.
  ///
  /// Task-mode agents are multi-turn and pause for user input. While one is
  /// waiting, the scheduler stops dispatching further parallel branches so the
  /// suspended task keeps exclusive control of the conversation.
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
    required String name,
  }) async {
    final BaseNode node = byName[name]!;
    if (node is RequestInput) {
      context.requestInputNodeKeys.add(name);
    }
    final Object? nodeInput = _nodeInput(
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
    } on NodeInterruptedError {
      return _NodeRunResult(
        name: name,
        output: null,
        interruptIds: nodeContext.interruptIds,
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
    required String fromNode,
    required Object? route,
    required Set<String> active,
    required Map<String, BaseNode> byName,
    required Map<String, Set<String>> dependencies,
    required Map<String, Set<String>> edgePredecessors,
    required Map<String, Set<String>> joinArrivals,
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
      if (targetNode.requiresAllPredecessors) {
        joinArrivals.putIfAbsent(target, () => <String>{}).add(fromNode);
      }
      if (reactivateCompleted && completed.contains(target)) {
        if (!targetNode.requiresAllPredecessors) {
          completed.remove(target);
          pending.add(target);
          for (final Set<String> arrivals in joinArrivals.values) {
            arrivals.remove(target);
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
    if (output == null) {
      return null;
    }
    final NodeInfo nodeInfo = _nodeInfoForOutput(
      context,
      author,
      outputForKeys: state?.outputFor,
    );
    final String? publishBranch =
        (output is Event && output.getFunctionResponses().isNotEmpty)
        ? (state?.branch ?? context.branch)
        : (state?.outputBranch ?? state?.branch ?? context.branch);
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

String _workflowRootPath(Workflow workflow, [InvocationContext? context]) {
  if (context != null && context.branch != null && context.branch!.isNotEmpty) {
    return context.branch!;
  }
  final String workflowName = workflow.name.isEmpty
      ? 'workflow'
      : workflow.name;
  return '$workflowName@1';
}

bool _isPreviouslyCompletedOutput(
  WorkflowResult? previousResult,
  String key, {
  required Iterable<Event> historyEvents,
  required String workflowPath,
}) {
  if (previousResult == null || !previousResult.outputs.containsKey(key)) {
    return false;
  }
  final NodeState? previousState = previousResult.nodeStates[key];
  if (previousState == null || !_isCompletedNodeState(previousState)) {
    return false;
  }
  final String nodePath = key.contains('@') ? key : '$key@1';
  final String fullNodePath = workflowPath.isEmpty
      ? nodePath
      : '$workflowPath/$nodePath';
  return historyEvents.any((Event event) {
    if (event.nodeInfo.path != fullNodePath) {
      return false;
    }
    return (event.hasOutput || event.content != null) &&
        event.getFunctionCalls().isEmpty &&
        event.getFunctionResponses().isEmpty &&
        event.longRunningToolIds?.isNotEmpty != true;
  });
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

void _validateStaticGraphEdges(Iterable<BaseNode> nodes, Iterable<Edge> edges) {
  final Map<String, BaseNode> byName = <String, BaseNode>{
    for (final BaseNode node in nodes) node.name: node,
  };
  _validateStartEdges(edges);
  _validateNoDuplicateEdges(edges);
  _validateDefaultRoutes(edges);
  for (final Edge edge in edges) {
    _validateChatModeEdge(edge, byName);
  }
  for (final BaseNode node in nodes) {
    final List<Edge> outgoing = edges
        .where((Edge edge) => edge.fromNode == node.name)
        .toList(growable: false);
    node.validateOutgoingEdges(outgoing);
  }
}

void _validateStartEdges(Iterable<Edge> edges) {
  for (final Edge edge in edges) {
    if (edge.fromNode == START && edge.route != null) {
      throw ArgumentError(
        'Graph validation failed. Edges from START must not have routes '
        '(edge to ${edge.toNode} has route ${edge.route}).',
      );
    }
  }
}

void _validateNoDuplicateEdges(Iterable<Edge> edges) {
  final Set<String> seen = <String>{};
  for (final Edge edge in edges) {
    final String key = '${edge.fromNode}\u0000${edge.toNode}';
    if (!seen.add(key)) {
      throw ArgumentError(
        'Graph validation failed. Duplicate edge found: '
        'from=${edge.fromNode}, to=${edge.toNode}',
      );
    }
  }
}

void _validateDefaultRoutes(Iterable<Edge> edges) {
  for (final Edge edge in edges) {
    if (edge.route is Iterable &&
        (edge.route as Iterable).contains(DEFAULT_ROUTE)) {
      throw ArgumentError(
        'Graph validation failed. DEFAULT_ROUTE cannot be combined with '
        'other routes in a list (edge from=${edge.fromNode}, to=${edge.toNode}). '
        'Use a separate edge for DEFAULT_ROUTE.',
      );
    }
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

/// Outcome of awaiting a single scheduled node task.
///
/// Wraps either a successful [_NodeRunResult] or a captured error so the
/// orchestration loop can process all completed sibling tasks in a batch
/// before propagating the first failure.
class _TaskOutcome {
  _TaskOutcome.success(_NodeRunResult this.result)
    : name = result.name,
      error = null,
      stackTrace = null;

  _TaskOutcome.failure(this.name, Object this.error, StackTrace this.stackTrace)
    : result = null;

  final String name;
  final _NodeRunResult? result;
  final Object? error;
  final StackTrace? stackTrace;
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
  String? parentKey,
}) async {
  final RetryConfig? retry = node.retryConfig;
  _validateRetryExceptionFilters(retry);
  final int maxAttempts = retry == null
      ? 1
      : (retry.maxAttempts < 1 ? 1 : retry.maxAttempts);
  final String key = stateKey ?? node.name;
  final NodeState state = context.nodeStates.putIfAbsent(key, NodeState.new);
  state.parentKey ??= parentKey;
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
      _updateNodeStatus(context, state, NodeStatus.cancelled);
      state.error = error;
      rethrow;
    }
    _updateNodeStatus(context, state, NodeStatus.running);
    state.attemptCount = attempt;
    context._failedInDynamicChild = false;
    final Map<String, int> countersAtStart = Map<String, int>.from(
      context._childRunCounters,
    );
    final Object? attemptInput = maxAttempts > 1
        ? _cloneNodeInputForAttempt(nodeInput)
        : nodeInput;
    try {
      Future<Object?> future = Future<Object?>.sync(
        () => node.run(context, attemptInput),
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
      // A node that ran to completion keeps its result even if a sibling
      // failed or the workflow was cancelled while it was in-flight. This
      // mirrors upstream's batch completion: sibling nodes that finish in the
      // same tick as a failure still have their outputs recorded. Nodes that
      // must abort early cooperatively check `context.throwIfCancelled()`
      // inside their own body.
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
      _updateNodeStatus(context, state, NodeStatus.completed);
      state.error = null;
      return output;
    } on AdkAbortException catch (error) {
      _updateNodeStatus(context, state, NodeStatus.cancelled);
      state.error = error;
      rethrow;
    } catch (error) {
      final bool failedInChild = context._failedInDynamicChild;
      lastError = error;
      _updateNodeStatus(context, state, NodeStatus.failed);
      state.error = error;
      if (attempt >= maxAttempts ||
          (failedInChild && node is ParallelWorker) ||
          !_shouldRetryError(error, retry)) {
        rethrow;
      }
      _resetDynamicChildrenForRetry(
        context,
        key,
        countersSnapshot: failedInChild ? countersAtStart : null,
      );
      await Future<void>.delayed(_retryDelay(retry!, attempt));
    }
  }
  throw StateError('Workflow node failed unexpectedly: $lastError');
}

void _resetDynamicChildrenForRetry(
  WorkflowContext context,
  String parentKey, {
  Map<String, int>? countersSnapshot,
}) {
  if (countersSnapshot != null) {
    context._childRunCounters
      ..clear()
      ..addAll(countersSnapshot);
  }
  context._outputDelegated = false;
  context._directOutput = null;
  context._hasDirectOutput = false;
  context.route = null;
  final Set<String> toPrune = <String>{};
  void collectFailedDescendants(String key) {
    for (final MapEntry<String, NodeState> entry
        in context.nodeStates.entries) {
      if (entry.value.parentKey == key) {
        if (!_isCompletedNodeState(entry.value)) {
          toPrune.add(entry.key);
        }
        collectFailedDescendants(entry.key);
      }
    }
  }

  collectFailedDescendants(parentKey);
  for (final String childKey in toPrune) {
    context.nodeStates.remove(childKey);
    context.outputs.remove(childKey);
  }
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
  if (retry == null ||
      error is WorkflowConfigurationError ||
      error is WorkflowInvariantError) {
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
    waiting:
        (node.waitForOutput ||
            node is Workflow ||
            (node is AgentNode && node.agent is Workflow)) &&
        !hasOutput &&
        route == null,
  );
}

bool _recordNodeResult(WorkflowContext context, _NodeRunResult result) {
  final NodeState? state = context.nodeStates[result.name];
  final Session? session = context.invocationContext?.session;
  if (session != null) {
    _mergeStateDelta(session, result.stateDelta);
  } else if (result.stateDelta.isNotEmpty) {
    context.state.addAll(result.stateDelta);
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
  } else {
    context.outputs.remove(result.name);
  }
  if (result.interruptIds.isNotEmpty || result.waiting) {
    if (state != null) {
      _updateNodeStatus(context, state, NodeStatus.waiting);
      state.interrupts
        ..clear()
        ..addAll(result.interruptIds);
    }
    return false;
  }
  if (result.output != null || result.route != null) {
    context.outputs[result.name] = result.output;
  } else {
    context.outputs.remove(result.name);
  }
  if (state != null) {
    state.interrupts.clear();
    state.resumeInputs.clear();
  }
  return true;
}

void _markTerminalOutputOwner(WorkflowContext context, String nodeName) {
  final NodeState? state = context.nodeStates[nodeName];
  for (final NodeState childState in context.nodeStates.values) {
    if (identical(childState, state)) {
      continue;
    }
    if (childState.outputFor.contains(nodeName)) {
      _addOutputOwner(childState.outputFor, _workflowOutputOwner);
    }
  }
  if (!context.outputs.containsKey(nodeName) ||
      context.outputs[nodeName] == null) {
    return;
  }
  if (state == null) {
    return;
  }
  _addOutputOwner(state.outputFor, nodeName);
  _addOutputOwner(state.outputFor, _workflowOutputOwner);
}

void _validateSingleTerminalOutput(
  WorkflowContext context,
  Set<String> terminalNodeNames, {
  required String workflowName,
}) {
  final List<String> terminalOutputs = <String>[
    for (final String nodeName in terminalNodeNames)
      if (context.outputs[nodeName] != null &&
          context.outputs[nodeName] is! RequestInput &&
          context.nodeStates[nodeName]?.status != NodeStatus.waiting)
        nodeName,
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

bool _seedNodeResumeInputs(
  NodeState state,
  Map<String, Object?> resumeInputs, {
  bool rerunOnResume = false,
}) {
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
  String? workflowPath,
}) {
  final String effectiveWorkflowName = workflowName.isEmpty
      ? 'workflow'
      : workflowName;
  final String effectiveWorkflowPath =
      workflowPath ?? '$effectiveWorkflowName@1';
  final Map<String, Object?> outputs = <String, Object?>{};
  final Map<String, NodeState> states = <String, NodeState>{};
  final Map<String, String> interruptOwner = <String, String>{};
  final Map<String, Object?> responseSchemas = <String, Object?>{};
  final Set<String> resumedWaitingNodes = <String>{};

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
        resumedWaitingNodes: resumedWaitingNodes,
      );
      continue;
    }

    final String path = event.nodeInfo.path;
    if (!_isWorkflowNodePath(path, effectiveWorkflowPath)) {
      continue;
    }

    final _WorkflowEventOwner? owner = _workflowEventOwnerForPath(
      path,
      workflowPath: effectiveWorkflowPath,
      staticNodes: staticNodes,
    );
    if (owner == null) {
      continue;
    }

    final NodeState state = stateFor(owner.key, owner.runId, owner.parentRunId);
    if (owner.runId != null) {
      final int prevCounter = state.runCounter;
      final int newCounter = _runCounterFromRunId(owner.runId);
      state.runId = owner.runId;
      if (newCounter > prevCounter) {
        state.runCounter = newCounter;
        if (prevCounter > 0 && staticNodes.containsKey(owner.key)) {
          // A static node started a new loop iteration: invalidate older
          // completed static nodes so downstream nodes re-run on resume.
          for (final MapEntry<String, NodeState> entry in states.entries) {
            if (entry.key == owner.key || !staticNodes.containsKey(entry.key)) {
              continue;
            }
            if (_isCompletedNodeState(entry.value) &&
                entry.value.runCounter < newCounter) {
              entry.value.status = NodeStatus.inactive;
            }
          }
        }
      }
    }
    final bool hasOutput = event.hasOutput || _hasMessageAsOutput(event);
    final bool hasClaimedBranch =
        hasOutput &&
        (event.nodeInfo.outputFor?.length ?? 0) > 1 &&
        event.getFunctionResponses().isEmpty;
    if (event.branch != null) {
      if (hasClaimedBranch) {
        state.outputBranch = event.branch;
      } else {
        state.branch = event.branch;
      }
    }
    final List<String>? outputFor = _outputKeysFromPaths(
      event.nodeInfo.outputFor,
      workflowPath: effectiveWorkflowPath,
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
    }

    final Object? eventOutput = _workflowOutputFromEvent(event);
    if (hasOutput) {
      outputs[owner.key] = eventOutput;
    }

    final bool hasResult = hasOutput || hasRoute;
    final bool hasError = event.errorCode != null;
    if (hasResult) {
      state.error = null;
      if (state.status != NodeStatus.waiting ||
          state.interrupts.isEmpty ||
          resumedWaitingNodes.contains(owner.key)) {
        state.status = NodeStatus.completed;
        state.interrupts.clear();
        state.resumeInputs.clear();
        resumedWaitingNodes.remove(owner.key);
      }
    } else if (hasError) {
      state.status = NodeStatus.failed;
      state.error = event.errorMessage ?? event.errorCode;
      outputs.remove(owner.key);
      resumedWaitingNodes.remove(owner.key);
    }

    final Set<String> interruptIds = _interruptIdsFromEvent(event);
    if (interruptIds.isEmpty) {
      if (!hasResult &&
          !hasError &&
          state.status != NodeStatus.failed &&
          (state.status != NodeStatus.waiting ||
              resumedWaitingNodes.contains(owner.key))) {
        final BaseNode? staticNode = staticNodes[owner.key];
        if (staticNode == null || !staticNode.waitForOutput) {
          state.status = NodeStatus.completed;
          state.interrupts.clear();
          state.resumeInputs.clear();
          outputs.remove(owner.key);
          resumedWaitingNodes.remove(owner.key);
        }
      }
      continue;
    }

    if (resumedWaitingNodes.remove(owner.key)) {
      state.interrupts.clear();
      state.resumeInputs.clear();
    }

    final RequestInput? requestInput = _requestInputFromEvent(event);
    if (requestInput != null) {
      outputs[owner.key] = requestInput;
    }
    state.status = NodeStatus.waiting;
    for (final String interruptId in interruptIds) {
      if (!state.interrupts.contains(interruptId)) {
        state.interrupts.add(interruptId);
      }
      state.resumeInputs.remove(interruptId);
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
  Set<String>? resumedWaitingNodes,
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

    final BaseNode? staticNode = staticNodes[ownerKey];
    if (staticNode != null && staticNode.rerunOnResume) {
      state.status = NodeStatus.waiting;
      resumedWaitingNodes?.add(ownerKey);
      continue;
    }

    if (state.interrupts.isNotEmpty) {
      state.status = NodeStatus.waiting;
      resumedWaitingNodes?.add(ownerKey);
      continue;
    }

    if (staticNode != null && !staticNode.rerunOnResume) {
      outputs[ownerKey] = _outputFromResumeInputs(state.resumeInputs);
      state.status = NodeStatus.completed;
      state.resumeInputs.clear();
      resumedWaitingNodes?.remove(ownerKey);
    } else {
      state.status = NodeStatus.waiting;
      resumedWaitingNodes?.add(ownerKey);
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
  final List<String> workflowPathSegments = _workflowPathSegments(workflowPath);
  if (segments.length < workflowPathSegments.length + 1) {
    return null;
  }
  for (int i = 0; i < workflowPathSegments.length; i += 1) {
    if (segments[i] != workflowPathSegments[i]) {
      return null;
    }
  }
  final String directChildSegment = segments[workflowPathSegments.length];
  final String directChildName = _workflowNodeNameFromSegment(
    directChildSegment,
  );
  final bool hasDescendants = segments.length > workflowPathSegments.length + 1;
  final String leaf = segments.last;
  final String leafName = _workflowNodeNameFromSegment(leaf);

  if (hasDescendants) {
    final String key = staticNodes.containsKey(directChildName)
        ? directChildName
        : directChildSegment;
    return _WorkflowEventOwner(
      key: key,
      runId: _workflowRunIdFromSegment(directChildSegment),
      parentRunId: _workflowRunIdFromSegment(workflowPathSegments.last),
    );
  } else {
    if (leafName.isEmpty) {
      return null;
    }
    final bool staticNode = staticNodes.containsKey(leafName);
    return _WorkflowEventOwner(
      key: staticNode ? leafName : leaf,
      runId: _workflowRunIdFromSegment(leaf),
      parentRunId: _workflowRunIdFromSegment(workflowPathSegments.last),
    );
  }
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
        outputBranch: entry.value.outputBranch,
        runCounter: entry.value.runCounter,
        runId: entry.value.runId,
        parentRunId: entry.value.parentRunId,
        parentKey: entry.value.parentKey,
        route: entry.value.route,
        error: entry.value.error,
      ),
  };
}

Object? _extractTaskOutput(
  Object? outputSchema,
  Map<String, dynamic> finishArgs,
) {
  if (outputSchema == null) {
    return finishArgs['result'];
  }
  if (outputSchema is Map) {
    final Object? type = outputSchema['type'];
    final bool isObjectSchema =
        type == 'object' ||
        (type == null && outputSchema.containsKey('properties'));
    if (isObjectSchema) {
      return Map<String, Object?>.from(finishArgs);
    }
  }
  if (finishArgs.length == 1 && finishArgs.containsKey('result')) {
    return finishArgs['result'];
  }
  return Map<String, Object?>.from(finishArgs);
}

Object? _cloneNodeInputForAttempt(Object? input) {
  if (input is Map) {
    return <Object?, Object?>{
      for (final MapEntry<Object?, Object?> entry in input.entries)
        entry.key: _cloneNodeInputForAttempt(entry.value),
    };
  }
  if (input is List) {
    return <Object?>[
      for (final Object? element in input) _cloneNodeInputForAttempt(element),
    ];
  }
  if (input is Set) {
    return <Object?>{
      for (final Object? element in input) _cloneNodeInputForAttempt(element),
    };
  }
  if (input is Content) {
    return input.copyWith();
  }
  return input;
}

bool _isCompletedNodeState(NodeState state) {
  return state.status == NodeStatus.completed ||
      state.status == NodeStatus.succeeded;
}

bool _hasUnresolvedWaitingInterrupts(
  NodeState? state, {
  bool rerunOnResume = false,
}) {
  if (state == null || state.status != NodeStatus.waiting) {
    return false;
  }
  if (rerunOnResume && state.resumeInputs.isNotEmpty) {
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
  Object? args = nodeInput;
  if (args is Content) {
    args = _textFromContent(args);
  }

  if (args is String) {
    final String trimmed = args.trim();
    if (trimmed.isEmpty) {
      args = null;
    } else {
      try {
        args = jsonDecode(trimmed);
      } catch (_) {
        // Leave as string to throw ArgumentError below.
      }
    }
  }

  if (args == null) {
    return <String, dynamic>{};
  }

  if (args is Map) {
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in args.entries)
        '${entry.key}': entry.value,
    };
  }

  throw ArgumentError(
    'The input to ToolNode must be a dictionary (Map), JSON string representing a Map, or null.',
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

/// Extracts and concatenates the non-thought text parts of a [Content] instance.
String _textFromContent(Content content) {
  return content.parts
      .where((Part part) => !part.thought && part.text != null)
      .map((Part part) => part.text!)
      .join();
}

/// Validates and sanitizes node input [data] against [schema].
///
/// Mirrors upstream's `validate_node_data(schema, data,
/// preserve_content=False)`: enforces the input boundary of an LlmAgent
/// workflow node before the payload is wrapped into [Content] for the model.
///
/// A `null` [schema] or [data] is returned unchanged. Descriptive JSON schemas
/// (a plain type-name [String]) are treated as pass-through. When [schema] is a
/// JSON-schema [Map], [Content] values are unwrapped to text and JSON strings
/// are parsed before validation. Throws [InputValidationError] when the data
/// does not satisfy the schema.
Object? validateNodeData(Object? schema, Object? data) {
  if (data == null || schema == null) {
    return data;
  }

  // Descriptive schemas (bare type-name strings) do not enforce structure.
  if (schema is! Map) {
    return data;
  }

  final Map<String, Object?> jsonSchema = <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in schema.entries)
      '${entry.key}': entry.value,
  };
  final Object? schemaType = jsonSchema['type'];

  Object? payload = data;
  if (payload is Content) {
    final String text = _textFromContent(payload);
    if (schemaType == 'string') {
      payload = text;
    } else {
      // Try to parse the text as JSON first, falling back to the raw string.
      try {
        payload = jsonDecode(text);
      } on FormatException {
        payload = text;
      }
    }
  } else if (payload is String && schemaType != 'string') {
    // A raw JSON string is parsed so it can be validated structurally.
    try {
      payload = jsonDecode(payload);
    } on FormatException {
      // Leave as-is; validation below reports the mismatch.
    }
  }

  final List<String> errors = <String>[];
  _validateNodeValue(payload, jsonSchema, path: r'$', errors: errors);
  if (errors.isNotEmpty) {
    throw InputValidationError(
      'Input does not match input schema:\n${errors.join('\n')}',
    );
  }
  return payload;
}

/// Validates [value] against a JSON [schema], appending failures to [errors].
void _validateNodeValue(
  Object? value,
  Map<String, Object?> schema, {
  required String path,
  required List<String> errors,
}) {
  final Object? type = schema['type'];
  switch (type) {
    case 'object':
      if (value is! Map) {
        errors.add('$path: expected object');
        return;
      }
      final Object? required = schema['required'];
      if (required is List) {
        for (final Object? field in required) {
          if (!value.containsKey(field)) {
            errors.add('$path.$field: missing required field');
          }
        }
      }
      final Object? properties = schema['properties'];
      if (properties is Map) {
        for (final MapEntry<Object?, Object?> entry in value.entries) {
          final Object? propSchema = properties['${entry.key}'];
          if (propSchema is Map) {
            _validateNodeValue(
              entry.value,
              <String, Object?>{
                for (final MapEntry<Object?, Object?> e in propSchema.entries)
                  '${e.key}': e.value,
              },
              path: '$path.${entry.key}',
              errors: errors,
            );
          }
        }
      }
      return;
    case 'array':
      if (value is! List) {
        errors.add('$path: expected array');
      }
      return;
    case 'string':
      if (value is! String) {
        errors.add('$path: expected string');
      }
      return;
    case 'integer':
      if (value is! int && !(value is num && value == value.toInt())) {
        errors.add('$path: expected integer');
      }
      return;
    case 'number':
      if (value is! num) {
        errors.add('$path: expected number');
      }
      return;
    case 'boolean':
      if (value is! bool) {
        errors.add('$path: expected boolean');
      }
      return;
    default:
      return;
  }
}

Object? _outputFromAgentEvent(Event event) {
  if (event.partial == true) {
    return null;
  }
  if (event.hasOutput) {
    return event.output;
  }
  final Content? content = event.content;
  if (content == null) {
    return null;
  }
  if (event.getFunctionCalls().isNotEmpty ||
      event.getFunctionResponses().isNotEmpty) {
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
    if (output.content == null) {
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

void _updateNodeStatus(
  WorkflowContext context,
  NodeState state,
  NodeStatus status,
) {
  if (state.status != status) {
    state.status = status;
    context.onNodeStateChange?.call();
  }
}

/// Exception thrown when a dynamic workflow node pauses for user input or an interrupt.
class NodeInterruptedError implements Exception {
  /// Creates a node interrupted error.
  NodeInterruptedError();
}
