part of 'workflow.dart';

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
    this.outputSchema,
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

  /// Optional output schema or type hint (such as [Uint8List]) for node output.
  final Object? outputSchema;

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
    super.outputSchema,
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
    super.outputSchema,
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
  bool? waitForOutput,
  RetryConfig? retryConfig,
  Duration? timeout,
  Object? outputSchema,
  Object? requireConfirmation,
}) {
  return buildNode(
        function,
        name: name,
        description: description,
        dependsOn: dependsOn,
        rerunOnResume: rerunOnResume,
        waitForOutput: waitForOutput,
        retryConfig: retryConfig,
        timeout: timeout,
        outputSchema: outputSchema,
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
  Object? outputSchema,
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
      outputSchema: outputSchema,
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
        outputSchema == null &&
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
      outputSchema: outputSchema,
    );
  }
  if (nodeLike is BaseAgent) {
    if (_hasConfirmationFlag(requireConfirmation)) {
      throw WorkflowConfigurationError(
        'require_confirmation is only supported on FunctionNode, got '
        '${nodeLike.runtimeType}.',
      );
    }
    if (nodeLike is LlmAgent && nodeLike.parallelWorker) {
      final int? maxParallelWorkers = nodeLike.maxParallelWorkers;
      nodeLike.maxParallelWorkers = null;
      nodeLike.parallelWorker = false;
      return ParallelWorker(
        node: nodeLike,
        maxParallelWorkers: maxParallelWorkers,
        retryConfig: retryConfig,
        timeout: timeout,
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
      outputSchema: outputSchema,
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
      outputSchema: outputSchema,
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

/// Returns whether [node] has an explicit [RetryConfig] configured directly or on its wrapped worker.
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
      outputSchema: node.outputSchema,
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
      outputSchema: node.outputSchema,
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
      outputSchema: node.outputSchema,
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
    super.outputSchema,
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
    super.outputSchema,
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
      llmAgent.mode ??= llmAgent.parentAgent != null ? 'chat' : 'single_turn';
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
    final Content? userContent;
    if (agent is LlmAgent) {
      final LlmAgent llmAgent = agent as LlmAgent;
      if ((llmAgent.mode == 'task' || llmAgent.mode == 'single_turn') &&
          validatedInput != null &&
          !isResuming) {
        userContent = _contentFromNodeInput(validatedInput);
      } else if (llmAgent.mode == 'single_turn' &&
          parentContext.isolationScope != null) {
        userContent = null;
      } else {
        userContent = parentContext.userContent;
      }
    } else {
      userContent = (validatedInput == null || isResuming)
          ? null
          : _contentFromNodeInput(validatedInput);
    }
    final String? nodeKey = context._currentNodeKey;
    final bool collectNestedWorkflowEvents =
        agent is Workflow &&
        nodeKey != null &&
        context.invocationContext != null;
    final String? currentNodePath =
        nodeKey != null && context.invocationContext != null
        ? _nodePathForOutputKey(parentContext, nodeKey)
        : null;
    final String? ownerPath = collectNestedWorkflowEvents
        ? currentNodePath
        : null;
    final String? nodeBranch =
        ownerPath ??
        (nodeKey != null ? context.nodeStates[nodeKey]?.branch : null) ??
        parentContext.branch;
    final bool isSingleTurnLlm =
        agent is LlmAgent && (agent as LlmAgent).mode == 'single_turn';
    final InvocationContext agentContext = parentContext.copyWith(
      agent: agent,
      userContent: userContent,
      branch: nodeBranch,
      nodePath: currentNodePath ?? parentContext.nodePath,
    )..userContent = userContent;
    if (isSingleTurnLlm) {
      agentContext.liveRequestQueue = null;
    }

    Event? injectedInputEvent;
    if (isSingleTurnLlm && userContent != null && !isResuming) {
      injectedInputEvent = Event(
        invocationId: agentContext.invocationId,
        author: 'user',
        content: userContent.copyWith(role: 'user'),
        branch: nodeBranch,
        isolationScope: agentContext.isolationScope,
        nodeInfo: currentNodePath != null
            ? NodeInfo(path: currentNodePath)
            : null,
      );
      agentContext.session.events.add(injectedInputEvent);
    } else if (isSingleTurnLlm && isResuming && currentNodePath != null) {
      for (final Event sessionEvent in agentContext.session.events) {
        if (sessionEvent.author == 'user' &&
            sessionEvent.nodeInfo.isEmpty &&
            sessionEvent.getFunctionResponses().any(
              (FunctionResponse fr) =>
                  fr.id != null && context.resumeInputs.containsKey(fr.id),
            )) {
          sessionEvent.nodeInfo = NodeInfo(path: currentNodePath);
        }
      }
    }

    final List<Event> nestedEvents = <Event>[];
    final List<Event> addedIntraNodeEvents = <Event>[];
    final bool isTaskMode =
        (agent is LlmAgent && (agent as LlmAgent).mode == 'task') ||
        (agent is RemoteA2aAgent && (agent as RemoteA2aAgent).mode == 'task');
    final bool isLive =
        agentContext.liveRequestQueue != null && !isSingleTurnLlm;
    final Set<String> taskSubagentToolNames = <String>{
      if (agent is LlmAgent && (agent as LlmAgent).mode == 'task')
        for (final Object tool in (agent as LlmAgent).tools)
          if (tool is TaskAgentTool) tool.name,
    };
    Map<String, dynamic>? pendingFinishArgs;
    String? pendingFinishCallId;
    String? rejectedFinishCallId;
    bool hasFinishedTaskOutput = false;
    Object? finishedTaskOutput;
    bool pausedOnInterrupt = false;
    Event? lastInterruptEvent;

    Event? finalEvent;
    try {
      final Stream<Event> eventStream = isLive
          ? agent.runLive(agentContext)
          : agent.runAsync(agentContext);
      await for (final Event event in eventStream) {
        if (agent is! Workflow) {
          if (currentNodePath != null && event.nodeInfo.isEmpty) {
            event.nodeInfo = NodeInfo(path: currentNodePath);
          }
          if (event.partial != true &&
              !agentContext.session.events.any(
                (Event existing) => existing.id == event.id,
              )) {
            agentContext.session.events.add(event);
            addedIntraNodeEvents.add(event);
          }
          PersistBarrier.markPersisted(agentContext, event.id);
        }
        _mergeStateDelta(agentContext.session, event.actions.stateDelta);
        if (isInterruptEvent(event)) {
          lastInterruptEvent = event;
        }
        if (hasFinishedTaskOutput) {
          // A sibling tool's pause request would strand the finished result.
          if (event.getFunctionCalls().isNotEmpty) {
            break;
          }
          // Let remaining non-call events (and agent/plugin after callbacks) run.
          continue;
        }
        if (isTaskMode) {
          final List<FunctionCall> calls = event.getFunctionCalls();
          final bool hasTaskSubagentCall = calls.any(
            (FunctionCall call) => taskSubagentToolNames.contains(call.name),
          );
          for (final FunctionCall call in calls) {
            if (call.name == finishTaskToolName) {
              if (!hasTaskSubagentCall) {
                pendingFinishArgs = Map<String, dynamic>.from(call.args);
                pendingFinishCallId = call.id;
              } else {
                rejectedFinishCallId = call.id;
              }
            }
          }
          for (final FunctionResponse response in event.getFunctionResponses()) {
            if (response.name == finishTaskToolName) {
              if (rejectedFinishCallId != null &&
                  response.id == rejectedFinishCallId) {
                response.response = <String, dynamic>{
                  'error':
                      'Cannot call finish_task in the same turn as a '
                      'task sub-agent tool call. Call finish_task after '
                      'the sub-agent result is available.',
                };
                // The rejected finish_task does not end the turn.
                event.actions.skipSummarization = null;
                rejectedFinishCallId = null;
                continue;
              }
              if (pendingFinishCallId == null ||
                  response.id == pendingFinishCallId) {
                if (response.response['result'] == finishTaskErrorResult ||
                    (event.errorMessage != null &&
                        event.errorMessage!.isNotEmpty)) {
                  return <String, Object?>{
                    'error': event.errorMessage ?? finishTaskErrorResult,
                  };
                }
                if (response.response['result'] == finishTaskSuccessResult &&
                    (pendingFinishArgs != null || event.hasOutput)) {
                  final Object? outputSchema = agent is LlmAgent
                      ? (agent as LlmAgent).outputSchema
                      : agent is RemoteA2aAgent
                      ? (agent as RemoteA2aAgent).outputSchema
                      : null;
                  final Object? taskOutput = event.hasOutput
                      ? event.output
                      : _extractTaskOutput(outputSchema, pendingFinishArgs!);
                  if (agent is LlmAgent) {
                    final LlmAgent llmAgent = agent as LlmAgent;
                    if (llmAgent.outputKey != null && taskOutput != null) {
                      agentContext.session.state[llmAgent.outputKey!] =
                          taskOutput;
                    }
                  }
                  finishedTaskOutput = taskOutput;
                  hasFinishedTaskOutput = true;
                  // A live session does not end on its own, and a transfer in
                  // the same turn runs at the parent; close the run here.
                  if (isLive ||
                      (event.actions.transferToAgent != null &&
                          event.actions.transferToAgent!.isNotEmpty)) {
                    return finishedTaskOutput;
                  }
                  continue;
                }
              }
            }
          }
        }
        if (event.isFinalResponse() &&
            event.actions.endOfAgent == null &&
            event.actions.agentState == null) {
          if (agent is! Workflow ||
              (event.nodeInfo.outputFor?.contains(
                    _workflowRootPath(agent as Workflow),
                  ) ??
                  false)) {
            finalEvent = event;
          }
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

      if (hasFinishedTaskOutput) {
        return finishedTaskOutput;
      }

      if (finalEvent == null) {
        if (lastInterruptEvent != null) {
          pausedOnInterrupt = true;
          agentContext.session.events.removeWhere(
            (Event e) => e.id == lastInterruptEvent!.id,
          );
          addedIntraNodeEvents.removeWhere(
            (Event e) => e.id == lastInterruptEvent!.id,
          );
          return lastInterruptEvent;
        }
        return null;
      }
      if (isSingleTurnLlm) {
        // A single_turn agent runs its transfer target inline, so the target's
        // reply is already this node's output. Clear any residual transfer so
        // downstream scheduling does not run the target again.
        finalEvent.actions.transferToAgent = null;
      }
      final Object? finalOutput = _outputFromAgentEvent(finalEvent);
      if (agent is LlmAgent) {
        final LlmAgent llmAgent = agent as LlmAgent;
        if (llmAgent.outputKey != null && finalOutput != null) {
          agentContext.session.state[llmAgent.outputKey!] = finalOutput;
        }
      }
      return finalOutput;
    } finally {
      if (!pausedOnInterrupt) {
        if (injectedInputEvent != null) {
          agentContext.session.events.removeWhere(
            (Event e) => e.id == injectedInputEvent!.id,
          );
        }
        if (isSingleTurnLlm && addedIntraNodeEvents.isNotEmpty) {
          final Set<String> addedIds = addedIntraNodeEvents
              .map((Event e) => e.id)
              .toSet();
          agentContext.session.events.removeWhere(
            (Event e) => addedIds.contains(e.id),
          );
        }
      }
    }
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
