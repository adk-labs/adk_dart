/// Wraps ADK sub-agents as tools callable from an Antigravity conversation.
library;

import '../../agents/base_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../runners/runner.dart';
import '../../sessions/in_memory_session_service.dart';
import '../../sessions/session.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';

/// Tool adapter that runs a child [BaseAgent] in an isolated [Runner] session.
///
/// ```dart
/// final subTool = SubAgentTool(helperAgent);
/// final reply = await subTool.call('Summarize the latest release notes.');
/// ```
class SubAgentTool extends BaseTool {
  /// Creates a [SubAgentTool] wrapping [child].
  SubAgentTool(this.child)
    : super(name: child.name, description: child.description);

  /// Wrapped child agent.
  final BaseAgent child;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'request': <String, Object?>{
            'type': 'string',
            'description': 'Request message forwarded to the sub-agent.',
          },
        },
        'required': <String>['request'],
      },
    );
  }

  /// Executes [child] in an isolated in-memory session with [request] as input.
  Future<String> call(String request) async {
    BaseAgent isolated;
    try {
      isolated = child.clone(
        update: <String, Object?>{'parentAgent': null},
      );
    } on UnsupportedError {
      isolated = child;
    }

    final InMemorySessionService sessionService = InMemorySessionService();
    final Runner runner = Runner(
      appName: child.name,
      agent: isolated,
      sessionService: sessionService,
    );
    try {
      final Session session = await sessionService.createSession(
        appName: child.name,
        userId: 'antigravity_sub_agent',
      );
      final Content content = Content(
        role: 'user',
        parts: <Part>[Part.text(request)],
      );
      String? lastText;
      String? lastError;
      await for (final Event event in runner.runAsync(
        userId: session.userId,
        sessionId: session.id,
        newMessage: content,
      )) {
        final List<Part>? parts = event.content?.parts;
        if (event.content?.role == 'model' && parts != null && parts.isNotEmpty) {
          final List<String> texts = <String>[
            for (final Part p in parts)
              if (p.text != null && p.text!.isNotEmpty && !p.thought) p.text!,
          ];
          if (texts.isNotEmpty) {
            lastText = texts.join('\n');
          }
        } else if (event.errorMessage != null &&
            event.errorMessage!.isNotEmpty) {
          lastError = event.errorMessage;
        }
      }
      return lastText ?? lastError ?? '';
    } finally {
      await runner.close();
    }
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String request =
        '${args['request'] ?? args['prompt'] ?? args['input'] ?? ''}';
    return call(request);
  }
}

/// Wraps [child] as a [SubAgentTool] callable by an Antigravity agent.
SubAgentTool makeSubAgentTool(BaseAgent child) {
  return SubAgentTool(child);
}
