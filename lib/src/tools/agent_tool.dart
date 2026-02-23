import 'dart:convert';

import '../agents/base_agent.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../runners/runner.dart';
import '../sessions/in_memory_session_service.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class AgentTool extends BaseTool {
  AgentTool({
    required this.agent,
    this.skipSummarization = false,
    this.includePlugins = true,
  }) : super(name: agent.name, description: agent.description);

  final BaseAgent agent;
  final bool skipSummarization;
  final bool includePlugins;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
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

    final String requestText = _resolveRequestText(args);
    final invocationContext = toolContext.invocationContext;
    final String childAppName = invocationContext.appName.isEmpty
        ? agent.name
        : invocationContext.appName;
    final Runner runner = Runner(
      appName: childAppName,
      agent: agent,
      artifactService: invocationContext.artifactService,
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
    }

    await runner.close();

    if (lastContent == null || lastContent.parts.isEmpty) {
      return '';
    }

    final String mergedText = lastContent.parts
        .where((Part part) => part.text != null && !part.thought)
        .map((Part part) => part.text!.trim())
        .where((String text) => text.isNotEmpty)
        .join('\n');
    return mergedText;
  }
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
