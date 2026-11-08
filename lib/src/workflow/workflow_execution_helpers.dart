part of 'workflow.dart';

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

// Outcome of awaiting a single scheduled node task.
//
// Wraps either a successful [_NodeRunResult] or a captured error so the
// orchestration loop can process all completed sibling tasks in a batch
// before propagating the first failure.
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
  if (state.status == NodeStatus.inactive ||
      state.runId == null ||
      (node.waitForOutput &&
          !_rerunsWhileWaiting(node) &&
          state.status == NodeStatus.waiting &&
          state.interrupts.isEmpty &&
          state.resumeInputs.isEmpty)) {
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
  final bool hasErrorOutput =
      rawOutput is Event &&
      (rawOutput.errorCode != null || rawOutput.errorMessage != null);
  final Object? workflowOutput = outputDelegated && !hasErrorOutput
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
      if (result.waiting && result.output == null) {
        state.outputFor.remove(_workflowOutputOwner);
      }
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
        final BaseNode? ownerStaticNode = staticNodes[owner.key];
        if (prevCounter > 0 &&
            ownerStaticNode != null &&
            !ownerStaticNode.waitForOutput) {
          // A static node started a new loop iteration: invalidate older
          // completed static nodes so downstream nodes re-run on resume.
          for (final MapEntry<String, NodeState> entry in states.entries) {
            if (entry.key == owner.key || !staticNodes.containsKey(entry.key)) {
              continue;
            }
            if (_isCompletedNodeState(entry.value) &&
                entry.value.runCounter < newCounter) {
              entry.value.status = NodeStatus.inactive;
              outputs.remove(entry.key);
              entry.value.outputFor.remove(_workflowOutputOwner);
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
        final bool isNativeEvent =
            event.author.isEmpty ||
            _workflowPathSegments(path)
                .map(_workflowNodeNameFromSegment)
                .contains(event.author);
        if (isNativeEvent || state.branch == null) {
          state.branch = event.branch;
        }
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

    final Object? eventOutput = _workflowOutputFromEvent(
      event,
      node: staticNodes[owner.key] ??
          staticNodes[_workflowNodeNameFromSegment(owner.key)],
    );
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
        } else {
          state.status = NodeStatus.waiting;
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

bool _expectsBytesOutput(BaseNode? node) {
  if (node == null) {
    return false;
  }
  final Object? schema = node.outputSchema;
  if (schema == Uint8List ||
      '$schema' == 'List<int>' ||
      schema == 'bytes' ||
      schema == 'Uint8List') {
    return true;
  }
  if (schema is Map &&
      (schema['format'] == 'byte' || schema['format'] == 'binary')) {
    return true;
  }
  if (node is FunctionNode) {
    final String fnType = node.function.runtimeType.toString();
    final int arrowIndex = fnType.lastIndexOf('=>');
    if (arrowIndex >= 0) {
      final String returnType = fnType.substring(arrowIndex + 2).trim();
      if (returnType.contains('Uint8List')) {
        return true;
      }
    }
  }
  return false;
}

Uint8List _decodeBase64Bytes(String encoded) {
  final String normalized = base64Url.normalize(encoded.trim());
  try {
    return base64Url.decode(normalized);
  } on FormatException {
    return base64.decode(base64.normalize(encoded.trim()));
  }
}

String _stripJsonCodeFence(String text) {
  final String trimmed = text.trim();
  if (!trimmed.startsWith('```')) {
    return text;
  }
  final int firstNewline = trimmed.indexOf('\n');
  if (firstNewline < 0) {
    return text;
  }
  final String body = trimmed.substring(firstNewline + 1);
  if (body.endsWith('```')) {
    return body.substring(0, body.length - 3).trim();
  }
  return text;
}

Object? _effectiveNodeOutputSchema(BaseNode? node) {
  if (node == null) {
    return null;
  }
  if (node.outputSchema != null) {
    return node.outputSchema;
  }
  if (node is AgentNode && node.agent is LlmAgent) {
    return (node.agent as LlmAgent).outputSchema;
  }
  if (node is AgentNode && node.agent is RemoteA2aAgent) {
    return (node.agent as RemoteA2aAgent).outputSchema;
  }
  return null;
}

Object? _workflowOutputFromEvent(Event event, {BaseNode? node}) {
  if (event.hasOutput) {
    final Object? raw = event.output;
    if (_expectsBytesOutput(node)) {
      if (raw is Uint8List) {
        return raw;
      }
      if (raw is String) {
        return _decodeBase64Bytes(raw);
      }
      if (raw is List<int>) {
        return Uint8List.fromList(raw);
      }
    }
    if (raw is String) {
      final Object? schema = _effectiveNodeOutputSchema(node);
      final bool isNonStringSchema =
          schema != null &&
          schema != String &&
          schema != 'string' &&
          !(schema is Map && schema['type'] == 'string');
      if (isNonStringSchema) {
        final String stripped = _stripJsonCodeFence(raw);
        try {
          return jsonDecode(stripped);
        } on FormatException {
          return stripped;
        }
      }
    }
    return raw;
  }
  if (!_hasMessageAsOutput(event)) {
    return null;
  }
  final Object? raw = _outputFromAgentEvent(event);
  if (raw is String) {
    final Object? schema = _effectiveNodeOutputSchema(node);
    final bool isNonStringSchema =
        schema != null &&
        schema != String &&
        schema != 'string' &&
        !(schema is Map && schema['type'] == 'string');
    if (isNonStringSchema) {
      final String stripped = _stripJsonCodeFence(raw);
      try {
        return jsonDecode(stripped);
      } on FormatException {
        return stripped;
      }
    }
  }
  return raw;
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

bool _rerunsWhileWaiting(BaseNode node) {
  return node.rerunOnResume || node is AgentNode || node is BaseAgent;
}

bool _isWaitingForPredecessorTrigger(NodeState? state, BaseNode? node) {
  if (state == null || node == null) {
    return false;
  }
  if (state.status != NodeStatus.waiting) {
    return false;
  }
  if (state.interrupts.isNotEmpty || state.resumeInputs.isNotEmpty) {
    return false;
  }
  return node.waitForOutput && !_rerunsWhileWaiting(node);
}

bool _usesTriggerBuffer(
  BaseNode node,
  Map<String, Set<String>> edgePredecessors,
) {
  return node.waitForOutput &&
      !node.requiresAllPredecessors &&
      node.dependsOn.isEmpty &&
      (edgePredecessors[node.name]?.isNotEmpty ?? false);
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

// Extracts and concatenates the non-thought text parts of a [Content] instance.
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

// Validates [value] against a JSON [schema], appending failures to [errors].
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
    if (context?._outputDelegated == true &&
        rawOutput.errorCode == null &&
        rawOutput.errorMessage == null &&
        rawOutput.hasOutput) {
      return rawOutput.copyWith(output: null);
    }
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
  NodeInterruptedError({Iterable<String>? interruptIds})
    : interruptIds = Set<String>.unmodifiable(interruptIds ?? const <String>{});

  /// Interrupt identifiers waiting for a response when the node paused.
  final Set<String> interruptIds;
}
