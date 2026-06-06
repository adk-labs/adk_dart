/// Tool adapter for delegating execution to nested agents.
library;

import 'dart:convert';

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
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
    await for (final Event event in runner.runAsync(
      userId: session.userId,
      sessionId: session.id,
      newMessage: Content.userText(requestText),
    )) {
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
    return null;
  }
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
