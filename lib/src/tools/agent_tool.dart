/// Tool adapter for delegating execution to nested agents.
library;

import 'dart:convert';

import '../agents/base_agent.dart';
import '../agents/invocation_context.dart';
import '../agents/llm_agent.dart';
import '../events/event.dart';
import '../flows/llm_flows/persist_barrier.dart';
import '../agents/llm/task/finish_task_tool.dart';
import '../models/llm_request.dart';
import '../plugins/plugin_manager.dart';
import '../runners/runner.dart';
import '../sessions/in_memory_session_service.dart';
import '../types/content.dart';
import 'base_tool.dart';
import '_forwarding_artifact_service.dart';
import 'tool_context.dart';

String _partToText(Part part) {
  final String? text = part.text;
  if (text != null && text.isNotEmpty) {
    return text;
  }

  final Object? codeExecutionResult = part.codeExecutionResult;
  if (codeExecutionResult != null) {
    final Map<String, Object?> result = _objectMap(codeExecutionResult);
    final String output =
        _stringValue(result['output']) ??
        _stringValue(result['result']) ??
        '$codeExecutionResult';
    return output.replaceFirst(RegExp(r'\n+$'), '');
  }

  final Object? executableCode = part.executableCode;
  if (executableCode != null) {
    final Map<String, Object?> code = _objectMap(executableCode);
    return _stringValue(code['code']) ?? '$executableCode';
  }

  return '';
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry<String, Object?>('$key', item),
    );
  }
  return <String, Object?>{};
}

String? _stringValue(Object? value) => value is String ? value : null;

const String _taskAgentToolSuffix =
    'IMPORTANT: This tool delegates execution to a specialized agent. '
    'Do NOT call this tool in parallel with any other tools.';

Map<String, dynamic> _defaultTaskInputSchema() {
  return <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'request': <String, dynamic>{
        'type': 'string',
        'description':
            'Detailed instructions or context for the task sub-agent.',
      },
    },
    'required': <String>['request'],
  };
}

/// Tool adapter that executes another agent as a tool call.
class AgentTool extends BaseTool {
  /// Creates a tool wrapper that delegates execution to [agent].
  AgentTool({
    required this.agent,
    this.skipSummarization = false,
    this.includePlugins = true,
    this.propagateGroundingMetadata = false,
  }) : super(name: agent.name, description: agent.description);

  /// Agent invoked by this tool.
  final BaseAgent agent;

  /// Whether model-side summarization is skipped after tool execution.
  final bool skipSummarization;

  /// Whether parent runner plugins are inherited by the child runner.
  final bool includePlugins;

  /// Whether child grounding metadata is made available to the parent response.
  final bool propagateGroundingMetadata;

  @override
  FunctionDeclaration? getDeclaration() {
    final Map<String, dynamic>? inputSchema = _schemaAsJsonMap(
      _getInputSchema(agent),
    );
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters:
          inputSchema ??
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'request': <String, dynamic>{'type': 'string'},
            },
            'required': <String>['request'],
          },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    if (skipSummarization) {
      toolContext.actions.skipSummarization = true;
    }

    final Object? inputSchema = _getInputSchema(agent);
    final String requestText = inputSchema == null
        ? _resolveRequestText(args)
        : jsonEncode(args);
    final Object? outputSchema = _getOutputSchema(agent);
    final invocationContext = toolContext.invocationContext;
    final String childAppName = invocationContext.appName.isEmpty
        ? agent.name
        : invocationContext.appName;
    final Runner runner = Runner(
      appName: childAppName,
      agent: agent,
      artifactService: ForwardingArtifactService(toolContext),
      sessionService: InMemorySessionService(),
      memoryService: invocationContext.memoryService,
      credentialService: invocationContext.credentialService,
      plugins: includePlugins
          ? invocationContext.pluginManager.plugins.toList(growable: false)
          : null,
    );
    if (includePlugins) {
      runner.pluginManager.setSkipClosingPlugins(true);
    }

    final Map<String, Object?> stateSnapshot = Map<String, Object?>.from(
      toolContext.state.toMap(),
    )..removeWhere((String key, Object? _) => key.startsWith('_adk'));
    final session = await runner.sessionService.createSession(
      appName: childAppName,
      userId: invocationContext.userId,
      state: stateSnapshot,
    );

    Content? lastContent;
    Object? lastGroundingMetadata;
    if (toolContext.abortSignal?.aborted == true) {
      await runner.close();
      return '';
    }
    await for (final Event event in runner.runAsync(
      userId: session.userId,
      sessionId: session.id,
      newMessage: Content.userText(requestText),
      abortSignal: toolContext.abortSignal,
    )) {
      if (toolContext.abortSignal?.aborted == true) {
        break;
      }
      if (event.actions.stateDelta.isNotEmpty) {
        toolContext.state.addAll(event.actions.stateDelta);
      }
      if (event.content != null) {
        lastContent = event.content;
      }
      if (event.groundingMetadata != null) {
        lastGroundingMetadata = event.groundingMetadata;
      }
    }

    await runner.close();

    if (propagateGroundingMetadata && lastGroundingMetadata != null) {
      toolContext.state['temp:_adk_grounding_metadata'] = lastGroundingMetadata;
    }

    if (lastContent == null || lastContent.parts.isEmpty) {
      return '';
    }

    final String mergedText = lastContent.parts
        .where((Part part) => !part.thought)
        .map(_partToText)
        .where((String text) => text.isNotEmpty)
        .join('\n');
    if (outputSchema != null && mergedText.isNotEmpty) {
      return jsonDecode(mergedText);
    }
    return mergedText;
  }
}

/// Tool adapter for a sub-agent configured with `mode: 'single_turn'`.
class SingleTurnAgentTool extends AgentTool {
  /// Creates a tool wrapper for a single-turn [agent].
  SingleTurnAgentTool({
    required super.agent,
    super.skipSummarization,
    super.includePlugins,
    super.propagateGroundingMetadata,
  });

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    if (skipSummarization) {
      toolContext.actions.skipSummarization = true;
    }

    final _InlineAgentRunResult result = await _runAgentInCurrentSession(
      agent: agent,
      args: args,
      toolContext: toolContext,
      branch: _childBranch(toolContext.invocationContext, agent),
      appendUserContent: true,
      includePlugins: includePlugins,
    );
    _propagateRunResult(
      result,
      toolContext,
      propagateGroundingMetadata: propagateGroundingMetadata,
    );

    return _resultFromLastContent(
      result.lastContent,
      outputSchema: _getOutputSchema(agent),
    );
  }
}

/// Tool adapter for a sub-agent configured with `mode: 'task'`.
class TaskAgentTool extends AgentTool {
  /// Creates a framework delegation marker for a task-mode [agent].
  TaskAgentTool({
    required super.agent,
    super.skipSummarization,
    super.includePlugins,
    super.propagateGroundingMetadata,
  }) {
    defersResponse = true;
  }

  @override
  FunctionDeclaration? getDeclaration() {
    final Map<String, dynamic> parameters =
        _schemaAsJsonMap(_getInputSchema(agent)) ?? _defaultTaskInputSchema();
    final String baseDescription = agent.description.trim();
    final String description = baseDescription.isEmpty
        ? _taskAgentToolSuffix
        : '$baseDescription\n$_taskAgentToolSuffix';
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: parameters,
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    if (skipSummarization) {
      toolContext.actions.skipSummarization = true;
    }

    final _InlineAgentRunResult result = await _runAgentInCurrentSession(
      agent: agent,
      args: args,
      toolContext: toolContext,
      branch: toolContext.invocationContext.branch,
      isolationScope: toolContext.functionCallId,
      appendUserContent: false,
      includePlugins: includePlugins,
    );
    _propagateRunResult(
      result,
      toolContext,
      propagateGroundingMetadata: propagateGroundingMetadata,
    );

    if (result.taskOutput != null) {
      return result.taskOutput;
    }
    final Object? fallback = _resultFromLastContent(
      result.lastContent,
      outputSchema: _getOutputSchema(agent),
    );
    return fallback == '' ? null : fallback;
  }
}

class _InlineAgentRunResult {
  Content? lastContent;
  Object? lastGroundingMetadata;
  Object? taskOutput;
}

Future<_InlineAgentRunResult> _runAgentInCurrentSession({
  required BaseAgent agent,
  required Map<String, dynamic> args,
  required ToolContext toolContext,
  required String? branch,
  required bool appendUserContent,
  required bool includePlugins,
  String? isolationScope,
}) async {
  final InvocationContext parentContext = toolContext.invocationContext;
  if (parentContext.isAborted) {
    return _InlineAgentRunResult();
  }

  final Object? nodeInput = _toolArgsToNodeInput(agent, args);
  final Content userContent = _nodeInputToContent(nodeInput);
  final InvocationContext childContext = parentContext.copyWith(
    agent: agent,
    branch: branch,
    isolationScope: isolationScope,
    userContent: userContent,
  );
  if (!includePlugins) {
    childContext.pluginManager = PluginManager();
  }

  if (appendUserContent) {
    await _appendInlineEvent(
      childContext,
      Event(
        invocationId: childContext.invocationId,
        author: 'user',
        branch: childContext.branch,
        isolationScope: childContext.isolationScope,
        content: userContent.copyWith(),
      ),
    );
  }

  final _InlineAgentRunResult result = _InlineAgentRunResult();
  Map<String, dynamic>? pendingFinishArgs;
  String? pendingFinishCallId;

  await for (final Event emitted in agent.runAsync(childContext)) {
    if (childContext.isAborted) {
      return result;
    }

    final Event? event = await _appendInlineEvent(childContext, emitted);
    if (event == null || childContext.isAborted) {
      return result;
    }

    if (event.actions.stateDelta.isNotEmpty) {
      toolContext.state.addAll(event.actions.stateDelta);
    }
    if (event.partial != true && event.content != null) {
      result.lastContent = event.content;
    }
    if (event.partial != true && event.groundingMetadata != null) {
      result.lastGroundingMetadata = event.groundingMetadata;
    }

    for (final FunctionCall call in event.getFunctionCalls()) {
      if (call.name == finishTaskToolName) {
        pendingFinishCallId = call.id;
        pendingFinishArgs = Map<String, dynamic>.from(call.args);
      }
    }

    for (final FunctionResponse response in event.getFunctionResponses()) {
      if (response.name == finishTaskToolName &&
          (pendingFinishCallId == null || response.id == pendingFinishCallId) &&
          _isFinishTaskSuccess(response.response) &&
          pendingFinishArgs != null) {
        result.taskOutput = _extractTaskOutput(agent, pendingFinishArgs);
        return result;
      }
    }
  }

  return result;
}

Future<Event?> _appendInlineEvent(
  InvocationContext context,
  Event event,
) async {
  if (context.isAborted) {
    return null;
  }
  event.isolationScope ??= context.isolationScope;
  final Event? modified = await context.pluginManager.runOnEventCallback(
    invocationContext: context,
    event: event,
  );
  if (context.isAborted) {
    return null;
  }
  final Event outputEvent = _mergeModifiedEvent(event, modified);
  final Event persisted = await context.sessionService.appendEvent(
    session: context.session,
    event: outputEvent,
  );
  PersistBarrier.markPersisted(context, outputEvent.id);
  if (event.id != outputEvent.id) {
    PersistBarrier.markPersisted(context, event.id);
  }
  return persisted;
}

Event _mergeModifiedEvent(Event original, Event? modified) {
  if (modified == null) {
    return original;
  }
  final Event merged = modified.copyWith();
  merged.invocationId = original.invocationId;
  merged.author = original.author;
  merged.branch ??= original.branch;
  merged.isolationScope ??= original.isolationScope;
  merged.id = original.id;
  merged.timestamp = original.timestamp;
  return merged;
}

Object? _toolArgsToNodeInput(BaseAgent agent, Map<String, dynamic> args) {
  if (_getInputSchema(agent) != null) {
    return args;
  }
  if (args.containsKey('request')) {
    return args['request'];
  }
  return args;
}

Content _nodeInputToContent(Object? nodeInput) {
  if (nodeInput is Content) {
    return nodeInput.copyWith(role: 'user');
  }
  if (nodeInput is String) {
    return Content.userText(nodeInput);
  }
  if (nodeInput is Map || nodeInput is List) {
    return Content.userText(jsonEncode(nodeInput));
  }
  if (nodeInput == null) {
    return Content.userText('');
  }
  return Content.userText('$nodeInput');
}

String _childBranch(InvocationContext context, BaseAgent agent) {
  final String suffix = '${context.agent.name}.${agent.name}';
  final String? branch = context.branch;
  if (branch == null || branch.isEmpty) {
    return suffix;
  }
  return '$branch.$suffix';
}

bool _isFinishTaskSuccess(Map<String, dynamic> response) {
  return response['result'] == finishTaskSuccessResult ||
      response['output'] == finishTaskSuccessResult;
}

Object? _extractTaskOutput(BaseAgent agent, Map<String, dynamic> args) {
  if (_usesObjectFinishTaskArgs(agent)) {
    return args;
  }
  return args['result'];
}

bool _usesObjectFinishTaskArgs(BaseAgent agent) {
  final Object? schema = _getOutputSchema(agent);
  if (schema == null) {
    return true;
  }
  final Map<String, dynamic>? map = _schemaAsJsonMap(schema);
  if (map != null) {
    final Object? type = map['type'];
    return type == null || '$type'.toLowerCase() == 'object';
  }
  if (schema is String) {
    return schema.toLowerCase() == 'object';
  }
  return schema == Map || schema == Object;
}

void _propagateRunResult(
  _InlineAgentRunResult result,
  ToolContext toolContext, {
  required bool propagateGroundingMetadata,
}) {
  if (propagateGroundingMetadata && result.lastGroundingMetadata != null) {
    toolContext.state['temp:_adk_grounding_metadata'] =
        result.lastGroundingMetadata;
  }
}

Object? _resultFromLastContent(Content? content, {Object? outputSchema}) {
  if (content == null || content.parts.isEmpty) {
    return '';
  }

  final String mergedText = content.parts
      .where((Part part) => !part.thought)
      .map(_partToText)
      .where((String text) => text.isNotEmpty)
      .join('\n');
  if (outputSchema != null && mergedText.isNotEmpty) {
    return jsonDecode(mergedText);
  }
  return mergedText;
}

Object? _getInputSchema(BaseAgent agent) {
  if (agent is LlmAgent) {
    return agent.inputSchema;
  }
  if (agent.subAgents.isNotEmpty) {
    return _getInputSchema(agent.subAgents.first);
  }
  return null;
}

Object? _getOutputSchema(BaseAgent agent) {
  if (agent is LlmAgent) {
    return agent.outputSchema;
  }
  if (agent.subAgents.isNotEmpty) {
    return _getOutputSchema(agent.subAgents.last);
  }
  return null;
}

Map<String, dynamic>? _schemaAsJsonMap(Object? schema) {
  if (schema is! Map) {
    return null;
  }
  return _deepJsonMap(schema);
}

Map<String, dynamic> _deepJsonMap(Map schema) {
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in schema.entries)
      '${entry.key}': _deepJsonValue(entry.value),
  };
}

Object? _deepJsonValue(Object? value) {
  if (value is Map) {
    return _deepJsonMap(value);
  }
  if (value is List) {
    return value.map(_deepJsonValue).toList(growable: false);
  }
  return value;
}

String _resolveRequestText(Map<String, dynamic> args) {
  if (args['request'] != null) {
    return '${args['request']}';
  }
  if (args.isEmpty) {
    return '';
  }
  return jsonEncode(args);
}
