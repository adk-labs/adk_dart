part of 'web_server.dart';

Map<String, Object?> _serializeAppSummary(Map<String, Object?> detail) {
  return <String, Object?>{
    'name': detail['name'],
    'rootAgentName': detail['root_agent_name'] ?? detail['rootAgentName'],
    'description': detail['description'],
    'language': detail['language'],
    'isComputerUse':
        detail['is_computer_use'] ?? detail['isComputerUse'] ?? false,
  };
}

Future<void> _handleTriggerRoute(
  HttpRequest request,
  _AdkDevWebContext context, {
  required TriggerRouter triggerRouter,
  required String appName,
  required String triggerSource,
}) async {
  try {
    if (triggerRouter.verifyAuth != null) {
      await triggerRouter.verifyAuth!(request);
    }
  } on TriggerAuthException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: error.statusCode,
      message: error.message,
    );
    return;
  }

  final Map<String, Object?> body;
  try {
    final Map<String, dynamic> decoded = await _readJsonBody(request);
    body = decoded.map((String key, dynamic value) => MapEntry(key, value));
  } on FormatException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: error.message,
    );
    return;
  }

  try {
    late final TriggerResponse response;
    if (triggerSource == 'pubsub') {
      final PubSubTriggerRequest triggerRequest =
          PubSubTriggerRequest.fromJson(body);
      response = await triggerRouter.handlePubSubRequest(
        appName: appName,
        triggerRequest: triggerRequest,
      );
    } else if (triggerSource == 'eventarc') {
      final Map<String, String> headers = <String, String>{};
      request.headers.forEach((String name, List<String> values) {
        if (values.isNotEmpty) {
          headers[name.toLowerCase()] = values.first;
        }
      });
      final EventarcTriggerRequest triggerRequest =
          EventarcTriggerRequest.fromJson(body, headers: headers);
      response = await triggerRouter.handleEventarcRequest(
        appName: appName,
        triggerRequest: triggerRequest,
      );
    } else {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Unknown trigger source: $triggerSource',
      );
      return;
    }

    await _writeJson(request, context, payload: response.toJson());
  } on SpecialAgentAccessDeniedException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.forbidden,
      message: error.message,
    );
  } on FormatException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: error.message,
    );
  } on ArgumentError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: '${error.message}',
    );
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
  } catch (_) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.internalServerError,
      message: 'Trigger execution failed',
      detail: 'Internal Server Error',
    );
  }
}

Future<void> _handleGetAppInfo(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
}) async {
  final Runner runner;
  try {
    runner = await context.getRunner(appName, request: request);
  } on ArgumentError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: '${error.message}',
    );
    return;
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  }

  final BaseAgent rootAgent = runner.agent;
  if (rootAgent is! LlmAgent) {
    await _writeJson(
      request,
      context,
      payload: graph_serialization.serializeAppInfo(
        App(
          name: appName,
          rootAgent: rootAgent,
          plugins: runner.pluginManager.plugins.toList(growable: false),
          contextCacheConfig: runner.contextCacheConfig,
          resumabilityConfig: runner.resumabilityConfig,
        ),
      ),
    );
    return;
  }

  final Map<String, Object?> appInfo = await _buildAppInfoPayload(
    context,
    appName: appName,
    rootAgent: rootAgent,
  );
  await _writeJson(request, context, payload: appInfo);
}

Future<Map<String, Object?>> _buildAppInfoPayload(
  _AdkDevWebContext context, {
  required String appName,
  required LlmAgent rootAgent,
}) async {
  Map<String, Object?>? summary;
  for (final Map<String, Object?> detail in context.listAppDetails()) {
    if (detail['name'] == appName) {
      summary = detail;
      break;
    }
  }

  return <String, Object?>{
    'name': appName,
    'rootAgentName': rootAgent.name,
    'description': rootAgent.description,
    'language': summary?['language'] ?? 'dart',
    'isComputerUse':
        _isComputerUseAgent(rootAgent) || (summary?['is_computer_use'] == true),
    'agents': await _collectAgentInfo(rootAgent),
  };
}

Future<Map<String, Object?>> _collectAgentInfo(LlmAgent rootAgent) async {
  final Map<String, Object?> agents = <String, Object?>{};

  Future<void> traverse(LlmAgent agent) async {
    if (agents.containsKey(agent.name)) {
      return;
    }

    final List<String> subAgentNames = <String>[];
    for (final BaseAgent subAgent in agent.subAgents) {
      if (subAgent is! LlmAgent) {
        continue;
      }
      subAgentNames.add(subAgent.name);
      await traverse(subAgent);
    }

    agents[agent.name] = <String, Object?>{
      'name': agent.name,
      'description': agent.description,
      'instruction': agent.instruction is String ? agent.instruction : '',
      'tools': await _serializeAgentTools(agent.tools),
      'subAgents': subAgentNames,
    };
  }

  await traverse(rootAgent);
  return agents;
}

Future<List<Map<String, Object?>>> _serializeAgentTools(
  List<Object> toolUnions,
) async {
  final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
  for (final Object toolUnion in toolUnions) {
    final List<FunctionDeclaration> declarations =
        await _extractFunctionDeclarations(toolUnion);
    if (declarations.isEmpty) {
      continue;
    }
    tools.add(<String, Object?>{
      'functionDeclarations': declarations
          .map(_serializeFunctionDeclaration)
          .toList(growable: false),
    });
  }
  return tools;
}

Future<List<FunctionDeclaration>> _extractFunctionDeclarations(
  Object toolUnion,
) async {
  if (toolUnion is BaseTool) {
    final FunctionDeclaration? declaration = toolUnion.getDeclaration();
    return declaration == null
        ? const <FunctionDeclaration>[]
        : <FunctionDeclaration>[declaration.copyWith()];
  }

  if (toolUnion is BaseToolset) {
    final List<FunctionDeclaration> declarations = <FunctionDeclaration>[];
    try {
      final List<BaseTool> tools = await toolUnion.getTools();
      for (final BaseTool tool in tools) {
        final FunctionDeclaration? declaration = tool.getDeclaration();
        if (declaration != null) {
          declarations.add(declaration.copyWith());
        }
      }
    } catch (_) {
      return const <FunctionDeclaration>[];
    }
    return declarations;
  }

  if (toolUnion is FunctionDeclaration) {
    return <FunctionDeclaration>[toolUnion.copyWith()];
  }

  if (toolUnion is Function) {
    return <FunctionDeclaration>[
      FunctionDeclaration(
        name: _inferFunctionToolName(toolUnion),
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      ),
    ];
  }

  if (toolUnion is Map<String, Object?> || toolUnion is String) {
    return <FunctionDeclaration>[buildFunctionDeclaration(toolUnion)];
  }

  return const <FunctionDeclaration>[];
}

Map<String, Object?> _serializeFunctionDeclaration(
  FunctionDeclaration declaration,
) {
  return <String, Object?>{
    'name': declaration.name,
    'description': declaration.description,
    'parameters': declaration.parameters,
  };
}

String _inferFunctionToolName(Function function) {
  final Match? quotedName = RegExp(r"'([^']+)'").firstMatch('$function');
  if (quotedName != null) {
    final String name = quotedName.group(1) ?? '';
    if (name.isNotEmpty) {
      return name;
    }
  }

  return 'tool_${function.hashCode.toUnsigned(32).toRadixString(16)}';
}

ComputerUseToolset? _findComputerUseToolset(BaseAgent agent) {
  final dynamic dynamicAgent = agent;
  try {
    if (dynamicAgent.tools is List) {
      for (final Object? tool in dynamicAgent.tools as List<Object?>) {
        if (tool is ComputerUseToolset) {
          return tool;
        }
      }
    }
  } catch (_) {}

  for (final BaseAgent subAgent in agent.subAgents) {
    final ComputerUseToolset? found = _findComputerUseToolset(subAgent);
    if (found != null) {
      return found;
    }
  }

  if (agent is Workflow) {
    for (final BaseNode node in agent.nodes) {
      if (node is AgentNode) {
        final ComputerUseToolset? found = _findComputerUseToolset(node.agent);
        if (found != null) {
          return found;
        }
      }
    }
  }
  return null;
}

bool _isComputerUseAgent(BaseAgent agent) {
  return _findComputerUseToolset(agent) != null;
}

Future<void> _handleScreencast(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
}) async {
  final Runner runner;
  try {
    runner = await context.getRunner(appName, request: request);
  } on ArgumentError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: '${error.message}',
    );
    return;
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  }

  final ComputerUseToolset? toolset = _findComputerUseToolset(runner.agent);
  if (toolset == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'No ComputerUseToolset found in app $appName.',
    );
    return;
  }

  if (!WebSocketTransformer.isUpgradeRequest(request)) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'WebSocket upgrade required.',
    );
    return;
  }

  final WebSocket socket = await WebSocketTransformer.upgrade(request);
  bool closed = false;
  socket.done.whenComplete(() {
    closed = true;
  });

  try {
    if (simulateScreencastInitErrorForTesting) {
      throw StateError('Simulated screencast initialization error');
    }
    await toolset.computer.initialize();
    while (!closed && socket.readyState == WebSocket.open) {
      try {
        final state = await toolset.computer.currentState();
        if (closed || socket.readyState != WebSocket.open) {
          break;
        }
        final List<int>? screenshot = state.screenshot;
        if (screenshot != null && screenshot.isNotEmpty) {
          socket.add(screenshot);
        }
      } catch (_) {
        // Ignore transient screenshot errors while streaming.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } catch (_) {
    // Ignore screencast streaming/initialization errors.
  } finally {
    if (socket.readyState == WebSocket.open) {
      await socket.close();
    }
  }
}

Future<void> _handleGetTraceByEventId(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String eventId,
}) async {
  final Map<String, Object?>? trace = context.readTraceByEventId(eventId);
  if (trace == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Trace not found',
    );
    return;
  }
  await _writeJson(request, context, payload: trace);
}

Future<void> _handleGetTraceDict(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String eventId,
}) {
  return _handleGetTraceByEventId(request, context, eventId: eventId);
}

Future<void> _handleGetTraceBySessionId(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String sessionId,
}) async {
  final List<Map<String, Object?>> trace = context.readTraceBySessionId(
    sessionId,
  );
  await _writeJson(request, context, payload: trace);
}

Future<void> _handleGetSessionTrace(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String sessionId,
}) {
  return _handleGetTraceBySessionId(request, context, sessionId: sessionId);
}

Set<(String, String)> _extractLiveHighlights(Event event) {
  final Set<(String, String)> highlights = <(String, String)>{};
  final List<FunctionCall> functionCalls = event.getFunctionCalls();
  final List<FunctionResponse> functionResponses = event.getFunctionResponses();

  if (functionCalls.isNotEmpty) {
    for (final FunctionCall call in functionCalls) {
      highlights.add((event.author, 'tool:${call.name}'));
    }
  } else if (functionResponses.isNotEmpty) {
    for (final FunctionResponse response in functionResponses) {
      highlights.add(('tool:${response.name}', event.author));
    }
  } else {
    highlights.add((event.author, ''));
  }
  return highlights;
}

Future<void> _handleGetEventGraph(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
  required String eventId,
}) async {
  final Event? event = await context.readSessionEvent(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
    eventId: eventId,
  );
  if (event == null) {
    await _writeJson(request, context, payload: const <String, Object?>{});
    return;
  }

  final Set<(String, String)> highlights = _extractLiveHighlights(event);

  final Runner runner = await context.getRunner(appName, request: request);
  final Map<String, NodeStatus> nodeStatuses = _nodeStatusesFromAgentState(
    event.actions.agentState,
  );
  final String dotSrc = await _buildAgentGraphDot(
    runner.agent,
    highlightPairs: highlights,
    nodeStatuses: nodeStatuses,
  );
  await _writeJson(
    request,
    context,
    payload: <String, Object?>{'dot_src': dotSrc},
  );
}

Future<void> _handleGetAppGraph(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
}) async {
  final Runner runner = await context.getRunner(appName, request: request);
  final String dotSrc = await _buildAgentGraphDot(runner.agent);
  await _writeJson(
    request,
    context,
    payload: <String, Object?>{'dot_src': dotSrc},
  );
}

Future<void> _handleGetAppGraphImage(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
}) {
  return _handleBuildGraphImage(request, context, appName: appName);
}

Future<void> _handleBuildGraphImage(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
}) async {
  final Runner runner = await context.getRunner(appName, request: request);
  final String? nodePath = request.uri.queryParameters['node'];
  final BaseAgent? targetAgent = _findGraphTarget(
    runner.agent,
    _splitNodePath(nodePath),
  );
  if (targetAgent == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Node not found: $nodePath',
    );
    return;
  }

  final String targetPath = nodePath == null ? '' : nodePath.trim();
  final Map<String, BaseAgent> targets = _collectWorkflowGraphTargets(
    targetAgent,
    currentPath: targetPath,
  );
  if (targets.isEmpty) {
    targets[targetPath] = targetAgent;
  }

  final Map<String, Object?> payload = <String, Object?>{};
  for (final MapEntry<String, BaseAgent> entry in targets.entries) {
    payload[entry.key] = <String, Object?>{
      'dot_src': await _buildAgentGraphDot(entry.value),
    };
  }
  await _writeJson(request, context, payload: payload);
}

Map<String, BaseAgent> _collectWorkflowGraphTargets(
  BaseAgent agent, {
  required String currentPath,
}) {
  final Map<String, BaseAgent> targets = <String, BaseAgent>{};
  if (agent is Workflow) {
    targets[currentPath] = agent;
    for (final BaseNode node in agent.nodes) {
      if (node is AgentNode) {
        final String childPath = _joinNodePath(currentPath, node.name);
        targets.addAll(
          _collectWorkflowGraphTargets(node.agent, currentPath: childPath),
        );
      }
    }
  }

  for (final BaseAgent subAgent in agent.subAgents) {
    final String childPath = _joinNodePath(currentPath, subAgent.name);
    targets.addAll(
      _collectWorkflowGraphTargets(subAgent, currentPath: childPath),
    );
  }
  return targets;
}

BaseAgent? _findGraphTarget(BaseAgent rootAgent, List<String> nodePath) {
  if (nodePath.isEmpty) {
    return rootAgent;
  }

  final List<String> path = nodePath.first == rootAgent.name
      ? nodePath.skip(1).toList(growable: false)
      : nodePath;
  return _findGraphTargetFrom(rootAgent, path);
}

BaseAgent? _findGraphTargetFrom(BaseAgent agent, List<String> path) {
  if (path.isEmpty) {
    return agent;
  }

  final String current = path.first;
  final List<String> rest = path.skip(1).toList(growable: false);
  for (final BaseAgent subAgent in agent.subAgents) {
    if (subAgent.name == current) {
      return _findGraphTargetFrom(subAgent, rest);
    }
  }

  if (agent is Workflow) {
    for (final BaseNode node in agent.nodes) {
      if (node is AgentNode &&
          (node.name == current || node.agent.name == current)) {
        return _findGraphTargetFrom(node.agent, rest);
      }
    }
  }
  return null;
}

List<String> _splitNodePath(String? nodePath) {
  if (nodePath == null) {
    return const <String>[];
  }
  return nodePath
      .split('/')
      .map((String segment) => segment.trim())
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
}

String _joinNodePath(String base, String child) {
  if (base.isEmpty) {
    return child;
  }
  return '$base/$child';
}

Future<String> _buildAgentGraphDot(
  BaseAgent rootAgent, {
  Set<(String, String)> highlightPairs = const <(String, String)>{},
  Map<String, NodeStatus> nodeStatuses = const <String, NodeStatus>{},
}) async {
  return agent_graph.getAgentGraphDot(
    rootAgent,
    highlightPairs: highlightPairs,
    nodeStatuses: nodeStatuses,
  );
}

Map<String, NodeStatus> _nodeStatusesFromAgentState(
  Map<String, Object?>? agentState,
) {
  final Object? rawNodes = agentState?['nodes'];
  if (rawNodes is! Map) {
    return const <String, NodeStatus>{};
  }

  final Map<String, NodeStatus> statuses = <String, NodeStatus>{};
  for (final MapEntry<dynamic, dynamic> entry in rawNodes.entries) {
    final String? nodeName = entry.key is String ? entry.key as String : null;
    if (nodeName == null || nodeName.isEmpty) {
      continue;
    }
    final Object? rawStatus = entry.value is Map
        ? (entry.value as Map<dynamic, dynamic>)['status']
        : entry.value;
    final NodeStatus? status = _parseNodeStatus(rawStatus);
    if (status != null) {
      statuses[nodeName] = status;
    }
  }
  return Map<String, NodeStatus>.unmodifiable(statuses);
}

NodeStatus? _parseNodeStatus(Object? value) {
  if (value is NodeStatus) {
    return value;
  }
  if (value is int && value >= 0 && value < NodeStatus.values.length) {
    return NodeStatus.values[value];
  }
  if (value is String) {
    final int? index = int.tryParse(value);
    if (index != null) {
      return _parseNodeStatus(index);
    }
    final String normalized = value
        .split('.')
        .last
        .replaceAll('-', '_')
        .toLowerCase();
    for (final NodeStatus status in NodeStatus.values) {
      if (status.name.toLowerCase() == normalized) {
        return status;
      }
    }
  }
  return null;
}

const String _initialStateFilename = 'initial_state.json';

Map<String, Object?> _loadInitialState(_AdkDevWebContext context, String appName) {
  final String? agentDir = context.getAgentDir(appName);
  if (agentDir == null) {
    return const <String, Object?>{};
  }
  final File file = File('$agentDir${Platform.pathSeparator}$_initialStateFilename');
  if (!file.existsSync()) {
    return const <String, Object?>{};
  }
  try {
    final String content = file.readAsStringSync(encoding: utf8);
    final dynamic decoded = jsonDecode(content);
    if (decoded is Map) {
      return Map<String, Object?>.from(
        decoded.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)),
      );
    }
  } catch (_) {
    // Missing, unreadable, or malformed file yields empty state.
  }
  return const <String, Object?>{};
}

Future<void> _handleLegacyCreateSession(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String userId = _validatePathIdentifier(
    _readString(payload, const <String>[
      'userId',
      'user_id',
    ], fallback: context.defaultUserId),
    'user_id',
  );
  final Map<String, Object?>? state = _readObjectMap(payload, const <String>[
    'state',
  ]);
  final Map<String, Object?> initialState = _loadInitialState(
    context,
    context.defaultAppName,
  );
  final Map<String, Object?>? mergedState = (initialState.isEmpty && state == null)
      ? null
      : <String, Object?>{
          ...initialState,
          ...?state,
        };
  final Session session = await context.sessionService.createSession(
    appName: context.defaultAppName,
    userId: userId,
    state: mergedState,
  );

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'session': _sessionToLegacyJson(session),
      'events': <Object?>[],
    },
  );
}

Future<void> _handleLegacyListSessions(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String userId = _validatePathIdentifier(
    request.uri.queryParameters['userId'] ?? context.defaultUserId,
    'user_id',
  );
  final ListSessionsResponse sessions = await context.sessionService
      .listSessions(appName: context.defaultAppName, userId: userId);

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'sessions': sessions.sessions
          .map<Map<String, Object?>>(_sessionToLegacyJson)
          .toList(growable: false),
    },
  );
}

Future<void> _handleLegacyPostMessage(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String userId = _validatePathIdentifier(
    _readString(payload, const <String>[
      'userId',
      'user_id',
    ], fallback: context.defaultUserId),
    'user_id',
  );
  final String validatedSessionId = _validatePathIdentifier(
    sessionId,
    'session_id',
  );
  final String text = _readString(payload, const <String>[
    'text',
  ], fallback: '').trim();

  if (text.isEmpty) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Message text is required.',
    );
    return;
  }

  final Runner runner = await context.getRunner(context.defaultAppName);
  final List<Event> events = await runner
      .runAsync(
        userId: userId,
        sessionId: validatedSessionId,
        newMessage: Content.userText(text),
      )
      .toList();
  final W3cTraceContext requestTraceContext = _extractRequestTraceContext(
    request,
  );
  for (final Event event in events) {
    context.recordTraceEvent(
      appName: context.defaultAppName,
      userId: userId,
      sessionId: validatedSessionId,
      event: event,
      traceContext: requestTraceContext,
    );
  }

  final String reply = _extractReplyText(
    events,
    fallbackAuthor: context.project.agentName,
  );

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'sessionId': validatedSessionId,
      'userId': userId,
      'events': events.map<Map<String, Object?>>(_eventToLegacyJson).toList(),
      if (reply.isNotEmpty) 'reply': reply,
    },
  );
}

Future<void> _handleLegacyGetEvents(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String sessionId,
}) async {
  final String userId = _validatePathIdentifier(
    request.uri.queryParameters['userId'] ?? context.defaultUserId,
    'user_id',
  );
  final String validatedSessionId = _validatePathIdentifier(
    sessionId,
    'session_id',
  );
  final Session? session = await context.sessionService.getSession(
    appName: context.defaultAppName,
    userId: userId,
    sessionId: validatedSessionId,
  );

  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found.',
    );
    return;
  }

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'session': _sessionToLegacyJson(session),
      'events': session.events
          .map<Map<String, Object?>>(_eventToLegacyJson)
          .toList(),
    },
  );
}

Future<void> _handleGetSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(session, includeEvents: true),
  );
}

Future<void> _handleListSessions(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
}) async {
  final ListSessionsResponse response = await context.sessionService
      .listSessions(appName: appName, userId: userId);

  await _writeJson(
    request,
    context,
    payload: response.sessions
        .map<Map<String, Object?>>((Session value) => _sessionToApiJson(value))
        .toList(growable: false),
  );
}

Future<void> _handleCreateSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String? requestedSessionId = _nullableString(payload, const <String>[
    'session_id',
    'sessionId',
  ]);
  final String? validatedRequestedSessionId = requestedSessionId == null
      ? null
      : _validatePathIdentifier(requestedSessionId, 'session_id');
  final Map<String, Object?>? state = _readObjectMap(payload, const <String>[
    'state',
  ]);
  final Map<String, Object?> initialState = _loadInitialState(context, appName);
  final Map<String, Object?>? mergedState = (initialState.isEmpty && state == null)
      ? null
      : <String, Object?>{
          ...initialState,
          ...?state,
        };

  final Session session = await context.sessionService.createSession(
    appName: appName,
    userId: userId,
    sessionId: validatedRequestedSessionId,
    state: mergedState,
  );

  final List<Event> seedEvents = _readEventsFromPayload(
    payload,
    appName: appName,
    userId: userId,
    sessionId: session.id,
  );
  for (final Event event in seedEvents) {
    await context.sessionService.appendEvent(
      session: session,
      event: markRestored(event),
    );
  }

  final Session? updated = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: session.id,
  );

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(updated ?? session, includeEvents: true),
  );
}

Future<void> _handleCreateSessionWithId(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final Map<String, Object?>? state = _readObjectMap(payload, const <String>[
    'state',
  ]);
  final Map<String, Object?> initialState = _loadInitialState(context, appName);
  final Map<String, Object?>? mergedState = (initialState.isEmpty && state == null)
      ? null
      : <String, Object?>{
          ...initialState,
          ...?state,
        };

  final Session session = await context.sessionService.createSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
    state: mergedState,
  );

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(session, includeEvents: true),
  );
}

Future<void> _handleDeleteSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  await context.sessionService.deleteSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleUpdateSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final Map<String, Object?> stateDelta =
      _readObjectMap(payload, const <String>['state_delta', 'stateDelta']) ??
      <String, Object?>{};

  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  final Event updateEvent = Event(
    invocationId: 'invocation_${DateTime.now().microsecondsSinceEpoch}',
    author: 'user',
    actions: EventActions(stateDelta: stateDelta),
  );
  await context.sessionService.appendEvent(
    session: session,
    event: updateEvent,
  );

  final Session? updated = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(updated ?? session, includeEvents: true),
  );
}

Future<void> _handlePatchMemory(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String sessionId = _validatePathIdentifier(
    _readString(payload, const <String>[
      'session_id',
      'sessionId',
    ], required: true),
    'session_id',
  );

  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  await context.memoryService.addSessionToMemory(session);
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleRewindSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String rewindBeforeInvocationId = _readString(
    payload,
    const <String>[
      'rewind_before_invocation_id',
      'rewindBeforeInvocationId',
      'invocation_id',
      'invocationId',
    ],
    required: true,
  );

  final Runner runner = await context.getRunner(appName);
  await context.cancelActiveSessionRuns(appName, userId, sessionId);
  try {
    await runner.rewindAsync(
      userId: userId,
      sessionId: sessionId,
      rewindBeforeInvocationId: rewindBeforeInvocationId,
    );
  } on SessionNotFoundError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  } on InvocationNotFoundError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  }

  final Session? updated = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (updated == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found: $sessionId',
    );
    return;
  }

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(updated, includeEvents: true),
  );
}

Future<void> _handleRun(HttpRequest request, _AdkDevWebContext context) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final _RunRequest runRequest = _parseRunRequest(payload, context);
  final Runner runner = await context.getRunner(
    runRequest.appName,
    request: request,
  );
  final bool shouldAutoCreateSession =
      runRequest.autoCreateSession ?? runner.autoCreateSession;

  final List<Event> events;
  final AdkAbortController abortController = AdkAbortController();
  final Completer<void> runCompleter = Completer<void>();
  context.registerActiveSessionRun(
    runRequest.appName,
    runRequest.userId,
    runRequest.sessionId,
    abortController,
    runCompleter.future,
  );
  request.response.done.then(
    (_) {},
    onError: (_) {
      if (!runCompleter.isCompleted) {
        abortController.abort('Client disconnected');
      }
    },
  );
  try {
    if (shouldAutoCreateSession) {
      await _ensureSessionExists(context, runRequest);
    }
    events = await runner
        .runAsync(
          userId: runRequest.userId,
          sessionId: runRequest.sessionId,
          newMessage: runRequest.newMessage,
          stateDelta: runRequest.stateDelta,
          invocationId: runRequest.invocationId,
          runConfig: context.maxLlmCalls == null
              ? null
              : RunConfig(maxLlmCalls: context.maxLlmCalls!),
          abortSignal: abortController.signal,
        )
        .toList();
    final W3cTraceContext requestTraceContext = _extractRequestTraceContext(
      request,
    );
    for (final Event event in events) {
      context.recordTraceEvent(
        appName: runRequest.appName,
        userId: runRequest.userId,
        sessionId: runRequest.sessionId,
        event: event,
        traceContext: requestTraceContext,
      );
    }
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  } on SessionNotFoundError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  } finally {
    if (!runCompleter.isCompleted) {
      runCompleter.complete();
    }
    context.unregisterActiveSessionRun(
      runRequest.appName,
      runRequest.userId,
      runRequest.sessionId,
      abortController,
      runCompleter.future,
    );
  }

  await _writeJson(
    request,
    context,
    payload: events
        .map<Map<String, Object?>>(
          (Event event) => _eventToApiJson(
            event,
            appName: runRequest.appName,
            userId: runRequest.userId,
            sessionId: runRequest.sessionId,
          ),
        )
        .toList(growable: false),
  );
}

Future<void> _ensureSessionExists(
  _AdkDevWebContext context,
  _RunRequest runRequest,
) async {
  final Session? existing = await context.sessionService.getSession(
    appName: runRequest.appName,
    userId: runRequest.userId,
    sessionId: runRequest.sessionId,
  );
  if (existing != null) {
    return;
  }

  try {
    await context.sessionService.createSession(
      appName: runRequest.appName,
      userId: runRequest.userId,
      sessionId: runRequest.sessionId,
    );
  } on Exception {
    final Session? created = await context.sessionService.getSession(
      appName: runRequest.appName,
      userId: runRequest.userId,
      sessionId: runRequest.sessionId,
    );
    if (created == null) {
      rethrow;
    }
  }
}

/// Returns true when this `/run_sse` request is resuming a paused tool call.
bool isFunctionResumeRequest({
  required String? invocationId,
  required Content? newMessage,
}) {
  if (invocationId == null || invocationId.trim().isEmpty) {
    return false;
  }
  final Content? message = newMessage;
  if (message == null || message.parts.isEmpty) {
    return false;
  }
  for (final Part part in message.parts) {
    if (part.functionResponse != null) {
      return true;
    }
  }
  return false;
}

/// Expands one streamed event into content/action events when needed.
List<Event> buildSseEventsForRun(Event event, {required bool isResumeRequest}) {
  final bool hasArtifactDelta = event.actions.artifactDelta.isNotEmpty;
  final bool hasContentParts = event.content?.parts.isNotEmpty ?? false;
  if (!hasArtifactDelta || !hasContentParts || isResumeRequest) {
    return <Event>[event];
  }
  final Event contentEvent = event.copyWith(
    actions: event.actions.copyWith(artifactDelta: <String, int>{}),
  );
  final Event artifactEvent = event.copyWith(content: null);
  return <Event>[contentEvent, artifactEvent];
}

Future<void> _handleRunSse(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final _RunRequest runRequest = _parseRunRequest(payload, context);
  final Runner runner = await context.getRunner(
    runRequest.appName,
    request: request,
  );
  final bool shouldAutoCreateSession =
      runRequest.autoCreateSession ?? runner.autoCreateSession;

  if (shouldAutoCreateSession) {
    await _ensureSessionExists(context, runRequest);
  } else {
    final Session? session = await context.sessionService.getSession(
      appName: runRequest.appName,
      userId: runRequest.userId,
      sessionId: runRequest.sessionId,
    );
    if (session == null) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Session not found: ${runRequest.sessionId}',
      );
      return;
    }
  }

  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  response.headers.set('Cache-Control', 'no-cache');
  response.headers.set('Connection', 'keep-alive');
  final bool resumeRequest = isFunctionResumeRequest(
    invocationId: runRequest.invocationId,
    newMessage: runRequest.newMessage,
  );
  final AdkAbortController abortController = AdkAbortController();
  final Completer<void> runCompleter = Completer<void>();
  context.registerActiveSessionRun(
    runRequest.appName,
    runRequest.userId,
    runRequest.sessionId,
    abortController,
    runCompleter.future,
  );
  var clientDisconnected = false;
  response.done.then(
    (_) {},
    onError: (_) {
      if (!runCompleter.isCompleted) {
        clientDisconnected = true;
        abortController.abort('SSE client disconnected');
      }
    },
  );

  final W3cTraceContext requestTraceContext = _extractRequestTraceContext(
    request,
  );
  try {
    await for (final Event event in runner.runAsync(
      userId: runRequest.userId,
      sessionId: runRequest.sessionId,
      newMessage: runRequest.newMessage,
      stateDelta: runRequest.stateDelta,
      invocationId: runRequest.invocationId,
      runConfig: RunConfig(
        streamingMode: runRequest.streaming
            ? StreamingMode.sse
            : StreamingMode.none,
        maxLlmCalls: context.maxLlmCalls ?? 500,
      ),
      abortSignal: abortController.signal,
    )) {
      if (abortController.signal.aborted) {
        break;
      }
      context.recordTraceEvent(
        appName: runRequest.appName,
        userId: runRequest.userId,
        sessionId: runRequest.sessionId,
        event: event,
        traceContext: requestTraceContext,
      );

      final List<Event> eventsToStream = buildSseEventsForRun(
        event,
        isResumeRequest: resumeRequest,
      );

      for (final Event streamEvent in eventsToStream) {
        final String data = jsonEncode(
          _eventToApiJson(
            streamEvent,
            appName: runRequest.appName,
            userId: runRequest.userId,
            sessionId: runRequest.sessionId,
          ),
        );
        try {
          if (simulateSseFlushErrorForTesting) {
            throw const SocketException('Simulated SSE client disconnect');
          }
          response.write('data: $data\n\n');
          await response.flush();
        } catch (_) {
          clientDisconnected = true;
          abortController.abort('SSE client disconnected');
          try {
            await response.close();
          } catch (_) {}
          return;
        }
      }
    }
  } catch (error) {
    if (!clientDisconnected && !abortController.signal.aborted) {
      response.write(
        'data: ${jsonEncode(<String, Object?>{'error': '$error'})}\n\n',
      );
    }
  } finally {
    if (!runCompleter.isCompleted) {
      runCompleter.complete();
    }
    context.unregisterActiveSessionRun(
      runRequest.appName,
      runRequest.userId,
      runRequest.sessionId,
      abortController,
      runCompleter.future,
    );
  }

  if (!clientDisconnected) {
    await response.close();
  }
}

Future<void> _handleRunLive(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String appName = _readRequiredQuery(request, 'app_name');
  final String userId = _validatePathIdentifier(
    _readRequiredQuery(request, 'user_id'),
    'user_id',
  );
  final String sessionId = _validatePathIdentifier(
    _readRequiredQuery(request, 'session_id'),
    'session_id',
  );

  final String? wsOrigin = _firstHeaderValue(request, 'origin');
  if (wsOrigin != null &&
      !_isRequestOriginAllowed(
        origin: wsOrigin,
        request: request,
        allowOrigins: context.allowOrigins,
        serverHost: context.serverHost,
      )) {
    await _writeText(
      request,
      context,
      statusCode: HttpStatus.forbidden,
      text: 'Forbidden: origin not allowed',
      includeCorsHeaders: false,
    );
    return;
  }

  // Guard before the websocket upgrade so the 403 can still be written as a
  // plain HTTP response.
  context._guardSpecialAgentAccess(appName, request: request);

  if (context.maxLiveSessions > 0 &&
      context.activeLiveSessions >= context.maxLiveSessions) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.serviceUnavailable,
      message: 'too many concurrent live sessions',
    );
    return;
  }

  context.activeLiveSessions += 1;
  try {
    final WebSocket socket = await WebSocketTransformer.upgrade(request);
    if (context.liveKeepaliveTimeout > Duration.zero) {
      socket.pingInterval = Duration(
        milliseconds: context.liveKeepaliveTimeout.inMilliseconds ~/ 2,
      );
    }

    final LiveRequestQueue liveQueue = LiveRequestQueue();
    final AdkAbortController abortController = AdkAbortController();
    final Runner runner = await context.getRunner(appName, request: request);
    final bool? proactiveAudio = _readOptionalBoolQuery(
      request,
      'proactive_audio',
    );
    final bool? enableAffectiveDialog = _readOptionalBoolQuery(
      request,
      'enable_affective_dialog',
    );
    final bool? enableSessionResumption = _readOptionalBoolQuery(
      request,
      'enable_session_resumption',
    );
    final bool saveLiveBlob =
        _readOptionalBoolQuery(request, 'save_live_blob') ?? false;
    final RunConfig runConfig = RunConfig(
      responseModalities: _parseModalities(
        request.uri.queryParameters['modalities'],
      ),
      proactivity: proactiveAudio == null
          ? null
          : <String, Object?>{'proactiveAudio': proactiveAudio},
      enableAffectiveDialog: enableAffectiveDialog,
      sessionResumption: enableSessionResumption == null
          ? null
          : <String, Object?>{'transparent': enableSessionResumption},
      saveLiveBlob: saveLiveBlob,
      maxLlmCalls: context.maxLlmCalls ?? 500,
    );

    int? closeCode;
    String closeReason = '';

    final W3cTraceContext requestTraceContext = _extractRequestTraceContext(
      request,
    );
    Future<void> forwardEvents() async {
      await for (final Event event in runner.runLive(
        liveRequestQueue: liveQueue,
        userId: userId,
        sessionId: sessionId,
        runConfig: runConfig,
        abortSignal: abortController.signal,
      )) {
        if (abortController.signal.aborted) {
          break;
        }
        context.recordTraceEvent(
          appName: appName,
          userId: userId,
          sessionId: sessionId,
          event: event,
          traceContext: requestTraceContext,
        );
        socket.add(
          jsonEncode(
            _eventToApiJson(
              event,
              appName: appName,
              userId: userId,
              sessionId: sessionId,
            ),
          ),
        );
      }
    }

    Future<void> processMessages() async {
      await for (final dynamic data in socket) {
        final int byteLength = data is String
            ? utf8.encode(data).length
            : (data is List<int> ? data.length : 0);
        if (context.maxLiveMessageBytes > 0 &&
            byteLength > context.maxLiveMessageBytes) {
          closeCode = WebSocketStatus.messageTooBig;
          closeReason = 'Live message exceeds maximum allowed size';
          abortController.abort();
          liveQueue.close();
          await socket.close(closeCode, closeReason);
          return;
        }
        if (data is String) {
          final LiveRequest liveRequest;
          try {
            final Object? decoded = jsonDecode(data);
            if (decoded is! Map) {
              throw const FormatException('LiveRequest must be a JSON object.');
            }
            liveRequest = _liveRequestFromJson(_toDynamicMap(decoded));
          } on Object {
            closeCode = WebSocketStatus.invalidFramePayloadData;
            closeReason = 'Invalid live request';
            return;
          }
          liveQueue.send(liveRequest);
        } else {
          liveQueue.sendRealtime(data);
        }
      }
    }

    final Future<void> forwardTask = forwardEvents();
    final Future<void> messageTask = processMessages();
    final Completer<void> liveCompleter = Completer<void>();
    context.registerActiveSessionRun(
      appName,
      userId,
      sessionId,
      abortController,
      liveCompleter.future,
    );

    try {
      await Future.any(<Future<void>>[forwardTask, messageTask]);
      closeCode ??= WebSocketStatus.normalClosure;
    } on SessionNotFoundError {
      closeCode = WebSocketStatus.protocolError;
      closeReason = 'Session not found';
    } catch (error) {
      closeCode = WebSocketStatus.internalServerError;
      final String reason = '$error';
      closeReason = reason.length > 123 ? reason.substring(0, 123) : reason;
    } finally {
      abortController.abort('WebSocket client disconnected');
      liveQueue.close();
      await forwardTask
          .catchError((Object _) {})
          .timeout(const Duration(milliseconds: 200), onTimeout: () {});
      await socket.close(closeCode, closeReason);
      if (!liveCompleter.isCompleted) {
        liveCompleter.complete();
      }
      context.unregisterActiveSessionRun(
        appName,
        userId,
        sessionId,
        abortController,
        liveCompleter.future,
      );
    }
  } finally {
    context.activeLiveSessions -= 1;
  }
}
